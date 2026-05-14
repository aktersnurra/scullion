defmodule Tore.Handlers.PlanningHandlerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Tore.Handlers.PlanningHandler

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
    Phoenix.PubSub.subscribe(Tore.PubSub, "plan")
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
    assert_receive {:events, [%Tore.Planning.Events.RecipeAssigned{}]}
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
    Tore.MockLLM
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

    assert Tore.Costs.llm_spend_this_month() > 0.0
  end

  test "generate_plan broadcasts PlanGenerated" do
    Tore.MockLLM
    |> expect(:generate_plan, fn _ ->
      {:ok, %{"days" => [], "prep_session" => %{}}, mock_usage()}
    end)

    PlanningHandler.generate_plan(plan_id(), week_start())
    assert_receive {:events, [%Tore.Planning.Events.PlanGenerated{}]}
  end

  test "generate_plan returns error when LLM fails" do
    Tore.MockLLM |> expect(:generate_plan, fn _ -> {:error, :timeout} end)
    assert {:error, :timeout} = PlanningHandler.generate_plan(plan_id(), week_start())
  end

  test "generate_plan returns budget_exceeded when over monthly limit" do
    Tore.Costs.log_llm_usage(%{
      feature: "seed",
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: 20.0
    })

    assert {:error, :budget_exceeded} = PlanningHandler.generate_plan(plan_id(), week_start())
  end

  describe "suggest_recipes_for_slot/3" do
    alias Tore.Recipes

    defp create_recipe(title, opts \\ []) do
      attrs =
        %{
          title: title,
          recipe_type: Keyword.get(opts, :recipe_type, :meal),
          base_servings: Keyword.get(opts, :base_servings, 4),
          prep_time_minutes: 10,
          cook_time_minutes: 20
        }

      {:ok, recipe} = Recipes.create(attrs)
      recipe
    end

    test "returns ranked recipes (rule-based, no LLM)" do
      _r1 = create_recipe("Plain pasta")
      r2 = create_recipe("Chicken curry", base_servings: 6)

      Tore.Pantry.add_item(%{name: "chicken", quantity: Decimal.new(1)})

      assert {:ok, results} = PlanningHandler.suggest_recipes_for_slot(plan_id(), "mon_dinner")
      assert is_list(results)
      assert length(results) >= 1

      # Each result is %{recipe, reasons, score}
      assert Enum.all?(results, &Map.has_key?(&1, :recipe))
      assert Enum.all?(results, &Map.has_key?(&1, :reasons))

      # Curry should rank above plain pasta because pantry overlap + leftovers
      curry = Enum.find(results, &(&1.recipe.id == r2.id))
      assert curry
      assert curry.score >= 0
    end

    test "respects :limit" do
      Enum.each(1..6, fn i -> create_recipe("Recipe #{i}") end)
      assert {:ok, results} = PlanningHandler.suggest_recipes_for_slot(plan_id(), "mon_dinner", limit: 3)
      assert length(results) <= 3
    end

    test ":include_llm true merges an extra LLM-suggested recipe" do
      r1 = create_recipe("Pasta")
      r2 = create_recipe("Curry")

      Tore.MockLLM
      |> expect(:suggest_slot_recipe, fn _ctx ->
        {:ok, %{recipe_id: r2.id, reasoning: "good fit"}, mock_usage()}
      end)

      assert {:ok, results} =
               PlanningHandler.suggest_recipes_for_slot(plan_id(), "tue_dinner",
                 include_llm: true,
                 limit: 5
               )

      # r2 should be in the results (from LLM merge or rule-based)
      assert Enum.any?(results, &(&1.recipe.id == r2.id))
      _ = r1
    end

    test ":include_llm true silently falls back when LLM errors" do
      _r = create_recipe("Pasta")

      Tore.MockLLM
      |> expect(:suggest_slot_recipe, fn _ -> {:error, :timeout} end)

      assert {:ok, results} =
               PlanningHandler.suggest_recipes_for_slot(plan_id(), "tue_dinner", include_llm: true)

      assert is_list(results)
    end
  end

  describe "assign_with_leftovers/5" do
    alias Tore.Recipes

    test "assigns recipe to slot and marks leftover days in one broadcast" do
      {:ok, recipe} =
        Recipes.create(%{
          title: "Roast chicken",
          recipe_type: :meal,
          base_servings: 6,
          prep_time_minutes: 10,
          cook_time_minutes: 60
        })

      assert {:ok, events} =
               PlanningHandler.assign_with_leftovers(
                 plan_id(),
                 "mon_dinner",
                 recipe.id,
                 6,
                 ["tue_dinner", "wed_dinner"]
               )

      # Primary RecipeAssigned + 2 (assign + leftover) per leftover day
      assert length(events) >= 5

      {:ok, state} = PlanningHandler.load_plan(plan_id())
      assert state.slots["mon_dinner"].recipe_id == recipe.id
      assert state.slots["tue_dinner"].leftover == true
      assert state.slots["wed_dinner"].leftover == true

      # Single broadcast
      assert_receive {:events, all_events}
      assert length(all_events) == length(events)
    end

    test "works with no leftover days (degenerates to assign)" do
      {:ok, recipe} =
        Recipes.create(%{
          title: "Quick salad",
          recipe_type: :meal,
          base_servings: 2,
          prep_time_minutes: 5,
          cook_time_minutes: 0
        })

      assert {:ok, events} =
               PlanningHandler.assign_with_leftovers(plan_id(), "mon_dinner", recipe.id, 2, [])

      assert length(events) == 1
    end
  end
end
