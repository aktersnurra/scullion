defmodule Tore.Handlers.GroceriesHandler do
  alias Tore.{EventStore, Groceries.Decider, Groceries.Commands, Groceries.Aggregator, Pantry}
  alias Phoenix.PubSub

  @pubsub Tore.PubSub
  @topic "grocery_list"

  def load_list(list_id) do
    EventStore.load(list_id, Decider)
  end

  def build_list(list_id, week_start, recipe_ids) do
    items = Aggregator.aggregate_by_ids(recipe_ids)
    run(list_id, %Commands.BuildList{week_start: week_start, items: items})
  end

  def add_item(list_id, name, quantity, unit, user_id) do
    run(list_id, %Commands.AddItem{
      item_id: Ecto.UUID.generate(),
      name: name,
      quantity: quantity,
      unit: unit,
      added_by: user_id
    })
  end

  def remove_item(list_id, item_id, user_id) do
    run(list_id, %Commands.RemoveItem{item_id: item_id, removed_by: user_id})
  end

  def check_item(list_id, item_id, user_id) do
    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(%Commands.CheckItem{item_id: item_id, checked_by: user_id}, state),
         :ok <- EventStore.append(list_id, events) do
      PubSub.broadcast(@pubsub, @topic, {:events, events})
      item = Map.get(state.items, item_id)
      if item, do: Pantry.add_item(%{name: item.name, quantity: item.quantity, unit: item.unit})
      {:ok, events}
    end
  end

  def uncheck_item(list_id, item_id, user_id) do
    run(list_id, %Commands.UncheckItem{item_id: item_id, unchecked_by: user_id})
  end

  def export_list(list_id) do
    with {:ok, state} <- EventStore.load(list_id, Decider) do
      lines =
        state.items
        |> Map.values()
        |> Enum.reject(& &1.checked)
        |> Enum.sort_by(& &1.name)
        |> Enum.map(fn item ->
          qty = if item.quantity, do: "#{item.quantity} #{item.unit} ", else: ""
          "- #{qty}#{item.name}"
        end)

      {:ok, Enum.join(lines, "\n")}
    end
  end

  defp run(list_id, command) do
    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(list_id, events) do
      PubSub.broadcast(@pubsub, @topic, {:events, events})
      {:ok, events}
    end
  end
end
