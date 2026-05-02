defmodule Scullion.Groceries.Decider do
  alias Scullion.Groceries.{Commands, Events, State}

  @spec initial() :: State.t()
  def initial, do: %State{}

  @spec decide(Commands.t(), State.t()) :: {:ok, [Events.t()]} | {:error, term()}
  def decide(%Commands.BuildList{week_start: ws, items: items}, _state) do
    {:ok, [%Events.ListBuilt{week_start: ws, items: items}]}
  end

  def decide(%Commands.AddItem{} = cmd, _state) do
    {:ok,
     [
       %Events.ItemAdded{
         item_id: cmd.item_id,
         name: cmd.name,
         quantity: cmd.quantity,
         unit: cmd.unit,
         added_by: cmd.added_by
       }
     ]}
  end

  def decide(%Commands.RemoveItem{item_id: id, removed_by: by}, state) do
    if Map.has_key?(state.items, id) do
      {:ok, [%Events.ItemRemoved{item_id: id, removed_by: by}]}
    else
      {:error, :item_not_found}
    end
  end

  def decide(%Commands.CheckItem{item_id: id, checked_by: by}, state) do
    if Map.has_key?(state.items, id) do
      {:ok, [%Events.ItemChecked{item_id: id, checked_by: by}]}
    else
      {:error, :item_not_found}
    end
  end

  def decide(%Commands.UncheckItem{item_id: id, unchecked_by: by}, state) do
    if Map.has_key?(state.items, id) do
      {:ok, [%Events.ItemUnchecked{item_id: id, unchecked_by: by}]}
    else
      {:error, :item_not_found}
    end
  end

  @spec evolve(State.t(), Events.t()) :: State.t()
  def evolve(state, %Events.ListBuilt{week_start: ws, items: items}) do
    item_map = Map.new(items, fn item -> {item.id, item} end)
    %{state | week_start: ws, items: item_map}
  end

  def evolve(state, %Events.ItemAdded{} = e) do
    item = %{id: e.item_id, name: e.name, quantity: e.quantity, unit: e.unit, checked: false}
    %{state | items: Map.put(state.items, e.item_id, item)}
  end

  def evolve(state, %Events.ItemRemoved{item_id: id}) do
    %{state | items: Map.delete(state.items, id)}
  end

  def evolve(state, %Events.ItemChecked{item_id: id}) do
    %{state | items: update_in(state.items, [id], &Map.put(&1, :checked, true))}
  end

  def evolve(state, %Events.ItemUnchecked{item_id: id}) do
    %{state | items: update_in(state.items, [id], &Map.put(&1, :checked, false))}
  end
end
