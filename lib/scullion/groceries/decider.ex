defmodule Scullion.Groceries.Decider do
  alias Scullion.Groceries.{Commands, Events, State}

  @spec initial() :: State.t()
  def initial, do: %State{}

  @spec decide(Commands.t(), State.t()) :: {:ok, [Events.t()]} | {:error, term()}
  def decide(%Commands.BuildList{}, _state), do: {:ok, []}
  def decide(%Commands.AddItem{}, _state), do: {:ok, []}
  def decide(%Commands.RemoveItem{}, _state), do: {:ok, []}
  def decide(%Commands.CheckItem{}, _state), do: {:ok, []}
  def decide(%Commands.UncheckItem{}, _state), do: {:ok, []}

  @spec evolve(State.t(), Events.t()) :: State.t()
  def evolve(state, %Events.ListBuilt{}), do: state
  def evolve(state, %Events.ItemAdded{}), do: state
  def evolve(state, %Events.ItemRemoved{}), do: state
  def evolve(state, %Events.ItemChecked{}), do: state
  def evolve(state, %Events.ItemUnchecked{}), do: state
end
