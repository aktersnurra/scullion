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

  test "ask_user is terminal-shaped", %{ctx: ctx} do
    tool = find("ask_user")
    assert {:ok, %{ask_user: "Which salmon?"}} = tool.run.(%{"question" => "Which salmon?"}, ctx)
  end
end
