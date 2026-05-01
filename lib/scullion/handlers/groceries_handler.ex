defmodule Scullion.Handlers.GroceriesHandler do
  alias Scullion.{EventStore, Groceries.Decider, Groceries.Commands}

  def check_item(list_id, item_id, user_id) do
    command = %Commands.CheckItem{item_id: item_id, checked_by: user_id}

    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(list_id, events) do
      Phoenix.PubSub.broadcast(Scullion.PubSub, "grocery_list:#{list_id}", {:events, events})
      {:ok, events}
    end
  end

  def uncheck_item(list_id, item_id, user_id) do
    command = %Commands.UncheckItem{item_id: item_id, unchecked_by: user_id}

    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(list_id, events) do
      Phoenix.PubSub.broadcast(Scullion.PubSub, "grocery_list:#{list_id}", {:events, events})
      {:ok, events}
    end
  end

  def add_item(list_id, attrs, user_id) do
    command = %Commands.AddItem{
      item_id: attrs[:item_id],
      name: attrs[:name],
      quantity: attrs[:quantity],
      unit: attrs[:unit],
      added_by: user_id
    }

    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(list_id, events) do
      Phoenix.PubSub.broadcast(Scullion.PubSub, "grocery_list:#{list_id}", {:events, events})
      {:ok, events}
    end
  end
end
