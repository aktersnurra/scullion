defmodule Tore.LLM.PlannerToolsTest do
  use Tore.DataCase, async: false
  alias Tore.LLM.PlannerTools
  alias Tore.Handlers.PlanningHandler

  @plan_id "plan:test"
  @week_start ~D[2026-06-01]

  setup do
    {:ok, _state} = PlanningHandler.load_plan(@plan_id)
    %{ctx: %{plan_id: @plan_id, week_start: @week_start}}
  end

  defp make_recipe(attrs \\ %{}) do
    base = %{title: "Recipe #{System.unique_integer([:positive])}", base_servings: 2, instructions: "x"}
    {:ok, r} = Tore.Recipes.create(Map.merge(base, attrs))
    r
  end

  defp find(name), do: Enum.find(PlannerTools.all(), &(&1.name == name))

  test "assign_recipe", %{ctx: ctx} do
    %{id: rid} = make_recipe(%{title: "Test Salmon"})

    tool = find("assign_recipe")
    args = %{"slot_key" => "mon_dinner", "recipe_id" => rid, "servings" => 2}

    assert :ok = Tore.LLM.Tool.validate_args(tool, args)
    assert {:ok, %{ok: true}} = tool.run.(args, ctx)

    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    assert %{recipe_id: ^rid, servings: 2} = state.slots["mon_dinner"]
  end

  test "assign_recipe returns the recipe title as label", %{ctx: ctx} do
    %{id: rid} = make_recipe(%{title: "Roast chicken"})
    tool = find("assign_recipe")

    assert {:ok, result} =
             tool.run.(%{"slot_key" => "mon_dinner", "recipe_id" => rid, "servings" => 4,
                         "rationale" => "easy"}, ctx)

    assert result.ok == true
    assert result.label == "Roast chicken"
  end

  # SkipMeal requires the slot to exist first (Decider returns :slot_empty otherwise).
  test "skip_meal", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    assign = find("assign_recipe")
    {:ok, _} = assign.run.(%{"slot_key" => "tue_dinner", "recipe_id" => rid, "servings" => 2}, ctx)

    tool = find("skip_meal")
    assert {:ok, %{ok: true}} = tool.run.(%{"slot_key" => "tue_dinner"}, ctx)
    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    assert state.slots["tue_dinner"].skipped == true
  end

  test "remove_recipe clears a slot", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    assign = find("assign_recipe")
    remove = find("remove_recipe")

    {:ok, _} = assign.run.(%{"slot_key" => "wed_dinner", "recipe_id" => rid, "servings" => 2}, ctx)
    {:ok, _} = remove.run.(%{"slot_key" => "wed_dinner"}, ctx)

    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    # After remove, the slot should either be absent or have nil recipe_id.
    slot = Map.get(state.slots, "wed_dinner")
    assert is_nil(slot) or is_nil(Map.get(slot, :recipe_id))
  end

  test "set_servings", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    assign = find("assign_recipe")
    set    = find("set_servings")

    {:ok, _} = assign.run.(%{"slot_key" => "thu_dinner", "recipe_id" => rid, "servings" => 2}, ctx)
    {:ok, _} = set.run.(%{"slot_key" => "thu_dinner", "servings" => 4}, ctx)

    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    assert state.slots["thu_dinner"].servings == 4
  end

  # MarkLeftover requires the slot to exist first (Decider returns :slot_empty otherwise).
  test "mark_leftover", %{ctx: ctx} do
    %{id: rid} = make_recipe()
    assign = find("assign_recipe")
    {:ok, _} = assign.run.(%{"slot_key" => "fri_dinner", "recipe_id" => rid, "servings" => 2}, ctx)

    tool = find("mark_leftover")
    assert {:ok, %{ok: true}} = tool.run.(%{"slot_key" => "fri_dinner"}, ctx)
    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    assert state.slots["fri_dinner"].leftover == true
  end

  test "swap_recipe moves a recipe between two slots", %{ctx: ctx} do
    %{id: rid} = make_recipe(%{title: "Salmon"})
    assign = find("assign_recipe")
    swap   = find("swap_recipe")

    {:ok, _} = assign.run.(%{"slot_key" => "tue_dinner", "recipe_id" => rid, "servings" => 2}, ctx)
    {:ok, _} = swap.run.(%{"from_slot_key" => "tue_dinner", "to_slot_key" => "fri_dinner"}, ctx)

    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    assert state.slots["fri_dinner"].recipe_id == rid
    tue = Map.get(state.slots, "tue_dinner")
    assert is_nil(tue) or is_nil(Map.get(tue, :recipe_id))
  end

  test "swap_recipe performs a true swap with no data loss and returns label", %{ctx: ctx} do
    %{id: a} = make_recipe(%{title: "Alpha"})
    %{id: b} = make_recipe(%{title: "Beta"})
    assign = find("assign_recipe")
    swap = find("swap_recipe")

    {:ok, _} = assign.run.(%{"slot_key" => "fri_dinner", "recipe_id" => a, "servings" => 4}, ctx)
    {:ok, _} = assign.run.(%{"slot_key" => "sun_dinner", "recipe_id" => b, "servings" => 2}, ctx)

    assert {:ok, result} =
             swap.run.(%{"from_slot_key" => "fri_dinner", "to_slot_key" => "sun_dinner",
                         "rationale" => "weekend"}, ctx)

    assert result.ok == true
    assert result.label == "Alpha"

    {:ok, state} = PlanningHandler.load_plan(@plan_id)
    assert state.slots["fri_dinner"].recipe_id == b
    assert state.slots["sun_dinner"].recipe_id == a
  end

  test "ask_user is terminal-shaped", %{ctx: ctx} do
    tool = find("ask_user")
    assert {:ok, %{ask_user: "Which salmon?"}} = tool.run.(%{"question" => "Which salmon?"}, ctx)
  end

  describe "read tools" do
    setup do
      {:ok, r1} =
        Tore.Recipes.create(%{
          title: "Quick Pasta",
          base_servings: 2,
          instructions: "x",
          prep_time_minutes: 5,
          cook_time_minutes: 15
        })

      {:ok, r2} =
        Tore.Recipes.create(%{
          title: "Slow Stew",
          base_servings: 4,
          instructions: "x",
          prep_time_minutes: 30,
          cook_time_minutes: 150
        })

      %{r1: r1, r2: r2, ctx: %{plan_id: "plan:test", week_start: ~D[2026-06-01]}}
    end

    test "search_recipes returns matches by query", %{r1: r1, ctx: ctx} do
      tool = Enum.find(Tore.LLM.PlannerTools.all(), &(&1.name == "search_recipes"))
      assert {:ok, %{recipes: results}} = tool.run.(%{"query" => "pasta"}, ctx)
      assert Enum.any?(results, fn r -> r.id == r1.id end)
    end

    test "search_recipes respects max_minutes", %{r1: r1, r2: r2, ctx: ctx} do
      tool = Enum.find(Tore.LLM.PlannerTools.all(), &(&1.name == "search_recipes"))
      assert {:ok, %{recipes: results}} = tool.run.(%{"max_minutes" => 30}, ctx)
      ids = Enum.map(results, & &1.id)
      assert r1.id in ids
      refute r2.id in ids
    end

    test "pantry_snapshot returns inventory", %{ctx: ctx} do
      {:ok, _} =
        Tore.Pantry.add_item(%{
          name: "olive oil",
          quantity: Decimal.new(1),
          unit: "bottle"
        })

      tool = Enum.find(Tore.LLM.PlannerTools.all(), &(&1.name == "pantry_snapshot"))
      assert {:ok, %{items: items}} = tool.run.(%{}, ctx)
      assert Enum.any?(items, &(&1.name == "olive oil"))
    end

    test "active_deals returns deals list", %{ctx: ctx} do
      tool = Enum.find(Tore.LLM.PlannerTools.all(), &(&1.name == "active_deals"))
      assert {:ok, %{deals: deals}} = tool.run.(%{}, ctx)
      assert is_list(deals)
    end
  end
end
