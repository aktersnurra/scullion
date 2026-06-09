defmodule Tore.LLM.PlannerToolsTest do
  use Tore.DataCase, async: false
  alias Tore.LLM.PlannerTools
  alias Tore.Planning.{Decider, State, Events}

  @week_start ~D[2026-06-01]

  setup do
    %{ctx: %{plan_id: "plan:test", week_start: @week_start}}
  end

  defp make_recipe(attrs \\ %{}) do
    base = %{
      title: "Recipe #{System.unique_integer([:positive])}",
      base_servings: 2,
      instructions: "x"
    }

    {:ok, r} = Tore.Recipes.create(Map.merge(base, attrs))
    r
  end

  defp find(name), do: Enum.find(PlannerTools.all(), &(&1.name == name))

  defp with_slot(state, slot, rid),
    do: Decider.evolve(state, %Events.RecipeAssigned{slot_key: slot, recipe_id: rid, servings: 2})

  test "assign_recipe proposes a RecipeAssigned event and evolves the plan", %{ctx: ctx} do
    %{id: rid} = make_recipe(%{title: "Test Salmon"})
    tool = find("assign_recipe")

    args = %{
      "slot_key" => "mon_dinner",
      "recipe_id" => rid,
      "servings" => 2,
      "rationale" => "good protein"
    }

    assert {:ok, %{ok: true}, events, next} = tool.run.(args, ctx, %State{})
    assert [%Events.RecipeAssigned{slot_key: "mon_dinner", recipe_id: ^rid, servings: 2}] = events
    assert %{recipe_id: ^rid, servings: 2} = next.slots["mon_dinner"]
  end

  test "assign_recipe returns the recipe title as label", %{ctx: ctx} do
    %{id: rid} = make_recipe(%{title: "Roast chicken"})
    tool = find("assign_recipe")

    args = %{
      "slot_key" => "mon_dinner",
      "recipe_id" => rid,
      "servings" => 4,
      "rationale" => "easy"
    }

    assert {:ok, %{ok: true, label: "Roast chicken"}, _events, _next} =
             tool.run.(args, ctx, %State{})
  end

  test "skip_meal on an occupied slot proposes MealSkipped", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    state = with_slot(%State{}, "tue_dinner", rid)
    tool = find("skip_meal")

    assert {:ok, %{ok: true}, [%Events.MealSkipped{slot_key: "tue_dinner"}], next} =
             tool.run.(%{"slot_key" => "tue_dinner", "rationale" => "out"}, ctx, state)

    assert next.slots["tue_dinner"].skipped == true
  end

  test "skip_meal on an empty slot returns the Decider error and does not evolve", %{ctx: ctx} do
    tool = find("skip_meal")

    assert {:error, :slot_empty} =
             tool.run.(%{"slot_key" => "fri_dinner", "rationale" => "out"}, ctx, %State{})
  end

  test "remove_recipe clears a slot", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    state = with_slot(%State{}, "mon_dinner", rid)
    tool = find("remove_recipe")

    assert {:ok, %{ok: true}, [%Events.RecipeRemoved{slot_key: "mon_dinner"}], next} =
             tool.run.(%{"slot_key" => "mon_dinner", "rationale" => "changed mind"}, ctx, state)

    refute Map.has_key?(next.slots, "mon_dinner")
  end

  test "set_servings changes servings", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    state = with_slot(%State{}, "mon_dinner", rid)
    tool = find("set_servings")

    assert {:ok, %{ok: true}, [%Events.ServingsChanged{slot_key: "mon_dinner", servings: 6}],
            next} =
             tool.run.(
               %{"slot_key" => "mon_dinner", "servings" => 6, "rationale" => "guests"},
               ctx,
               state
             )

    assert next.slots["mon_dinner"].servings == 6
  end

  test "mark_leftover marks the slot", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    state = with_slot(%State{}, "tue_dinner", rid)
    tool = find("mark_leftover")

    assert {:ok, %{ok: true}, [%Events.LeftoverMarked{slot_key: "tue_dinner"}], next} =
             tool.run.(%{"slot_key" => "tue_dinner", "rationale" => "leftovers"}, ctx, state)

    assert next.slots["tue_dinner"].leftover == true
  end

  test "swap_recipe cross-assigns two slots", %{ctx: ctx} do
    r1 = make_recipe(%{title: "One"})
    r2 = make_recipe(%{title: "Two"})
    state = %State{} |> with_slot("mon_dinner", r1.id) |> with_slot("tue_dinner", r2.id)
    tool = find("swap_recipe")

    assert {:ok, %{ok: true, recipe_id: rid, label: "One"}, events, next} =
             tool.run.(
               %{
                 "from_slot_key" => "mon_dinner",
                 "to_slot_key" => "tue_dinner",
                 "rationale" => "balance"
               },
               ctx,
               state
             )

    assert rid == r1.id
    assert next.slots["tue_dinner"].recipe_id == r1.id
    assert next.slots["mon_dinner"].recipe_id == r2.id
    assert events != []
  end

  test "read tools return the plan unchanged with no events", %{ctx: ctx} do
    tool = find("search_recipes")
    assert {:ok, %{recipes: _}, [], %State{}} = tool.run.(%{"query" => "x"}, ctx, %State{})
  end

  test "ask_user returns the question with the plan unchanged", %{ctx: ctx} do
    tool = find("ask_user")

    assert {:ok, %{ask_user: "which day?"}, [], %State{}} =
             tool.run.(%{"question" => "which day?"}, ctx, %State{})
  end
end
