defmodule Scullion.Handlers.PlanningHandler do
  alias Scullion.{EventStore, Planning.Decider, Planning.Commands}

  def generate_plan(week_start, constraints) do
    plan_id = "plan:#{week_start}"
    command = %Commands.GeneratePlan{week_start: week_start, recipes: constraints}

    with {:ok, state} <- EventStore.load(plan_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(plan_id, events) do
      {:ok, events}
    end
  end

  def assign_recipe(week_start, day, recipe_id, servings) do
    plan_id = "plan:#{week_start}"
    command = %Commands.AssignRecipe{day: day, recipe_id: recipe_id, servings: servings}

    with {:ok, state} <- EventStore.load(plan_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(plan_id, events) do
      {:ok, events}
    end
  end

  def remove_recipe(week_start, day) do
    plan_id = "plan:#{week_start}"
    command = %Commands.RemoveRecipe{day: day}

    with {:ok, state} <- EventStore.load(plan_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(plan_id, events) do
      {:ok, events}
    end
  end
end
