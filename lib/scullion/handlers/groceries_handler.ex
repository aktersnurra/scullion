defmodule Scullion.Handlers.GroceriesHandler do
  alias Scullion.{EventStore, Groceries.Decider, Groceries.Commands, Groceries.Aggregator}
  alias Phoenix.PubSub

  @pubsub Scullion.PubSub
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
    run(list_id, %Commands.CheckItem{item_id: item_id, checked_by: user_id})
  end

  def uncheck_item(list_id, item_id, user_id) do
    run(list_id, %Commands.UncheckItem{item_id: item_id, unchecked_by: user_id})
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
