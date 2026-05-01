defmodule Scullion.Planning.Decider do
  alias Scullion.Planning.{Commands, Events, State}

  @spec initial() :: State.t()
  def initial, do: %State{}

  @spec decide(Commands.t(), State.t()) :: {:ok, [Events.t()]} | {:error, term()}
  def decide(%Commands.GeneratePlan{}, _state), do: {:ok, []}
  def decide(%Commands.AssignRecipe{}, _state), do: {:ok, []}
  def decide(%Commands.RemoveRecipe{}, _state), do: {:ok, []}
  def decide(%Commands.SetServings{}, _state), do: {:ok, []}
  def decide(%Commands.MarkLeftover{}, _state), do: {:ok, []}

  @spec evolve(State.t(), Events.t()) :: State.t()
  def evolve(state, %Events.PlanGenerated{}), do: state
  def evolve(state, %Events.RecipeAssigned{}), do: state
  def evolve(state, %Events.RecipeRemoved{}), do: state
  def evolve(state, %Events.ServingsChanged{}), do: state
  def evolve(state, %Events.LeftoverMarked{}), do: state
end
