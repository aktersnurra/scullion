defmodule Scullion.Handlers.PlanningHandlerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Scullion.Handlers.PlanningHandler

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Scullion.Repo)
    Phoenix.PubSub.subscribe(Scullion.PubSub, "plan")
    :ok
  end

  defp plan_id, do: "plan:2026-04-27"
  defp week_start, do: ~D[2026-04-27]

  defp mock_usage, do: %{prompt_tokens: 100, completion_tokens: 50, cost_usd: 0.001}

  test "load_plan returns initial state for new plan" do
    assert {:ok, state} = PlanningHandler.load_plan(plan_id())
    assert state.slots == %{}
  end

  test "assign_recipe persists RecipeAssigned event" do
    assert {:ok, _events} = PlanningHandler.assign_recipe(plan_id(), "mon_dinner", 1, 4)
    assert {:ok, state} = PlanningHandler.load_plan(plan_id())
    assert state.slots["mon_dinner"].recipe_id == 1
    assert state.slots["mon_dinner"].servings == 4
  end

  test "assign_recipe broadcasts to plan topic" do
    PlanningHandler.assign_recipe(plan_id(), "tue_dinner", 2, 2)
    assert_receive {:events, [%Scullion.Planning.Events.RecipeAssigned{}]}
  end

  test "remove_recipe returns error for empty slot" do
    assert {:error, :slot_empty} = PlanningHandler.remove_recipe(plan_id(), "mon_dinner")
  end

  test "load_plan returns current state after multiple events" do
    PlanningHandler.assign_recipe(plan_id(), "mon_dinner", 10, 4)
    PlanningHandler.assign_recipe(plan_id(), "tue_dinner", 11, 2)
    PlanningHandler.skip_meal(plan_id(), "mon_dinner")

    {:ok, state} = PlanningHandler.load_plan(plan_id())
    assert state.slots["mon_dinner"].skipped == true
    assert state.slots["tue_dinner"].recipe_id == 11
  end

  test "generate_plan calls LLM, logs usage, persists PlanGenerated" do
    Scullion.MockLLM
    |> expect(:generate_plan, fn _ctx ->
      {:ok,
       %{
         "days" => [
           %{"slot_key" => "mon_dinner", "recipe_id" => 999, "servings" => 4,
             "cascade_from" => nil, "notes" => ""}
         ],
         "prep_session" => %{}
       }, mock_usage()}
    end)

    assert {:ok, _events} = PlanningHandler.generate_plan(plan_id(), week_start())
    {:ok, state} = PlanningHandler.load_plan(plan_id())
    assert state.slots["mon_dinner"].recipe_id == 999

    assert Scullion.Costs.llm_spend_this_month() > 0.0
  end

  test "generate_plan broadcasts PlanGenerated" do
    Scullion.MockLLM
    |> expect(:generate_plan, fn _ ->
      {:ok, %{"days" => [], "prep_session" => %{}}, mock_usage()}
    end)

    PlanningHandler.generate_plan(plan_id(), week_start())
    assert_receive {:events, [%Scullion.Planning.Events.PlanGenerated{}]}
  end

  test "generate_plan returns error when LLM fails" do
    Scullion.MockLLM |> expect(:generate_plan, fn _ -> {:error, :timeout} end)
    assert {:error, :timeout} = PlanningHandler.generate_plan(plan_id(), week_start())
  end

  test "generate_plan returns budget_exceeded when over monthly limit" do
    Scullion.Costs.log_llm_usage(%{
      feature: "seed",
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: 20.0
    })

    assert {:error, :budget_exceeded} = PlanningHandler.generate_plan(plan_id(), week_start())
  end
end
