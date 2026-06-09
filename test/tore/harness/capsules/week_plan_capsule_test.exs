defmodule Tore.Harness.Capsules.WeekPlanCapsuleTest do
  use Tore.DataCase, async: false

  alias Tore.Harness.Capsules.WeekPlanCapsule, as: Capsule
  alias Tore.{Handlers.PlanningHandler, Recipes}

  defp ctx_for(week_start) do
    %{
      household_id: 1,
      plan_stream_id: "plan:#{Date.to_iso8601(week_start)}",
      week_start: week_start
    }
  end

  test "build/1 has seven slots, Monday through Sunday, with statuses" do
    week_start = ~D[2026-06-08]
    ctx = ctx_for(week_start)

    {:ok, recipe} =
      Recipes.create(%{
        title: "Roast chicken",
        recipe_type: :meal,
        base_servings: 4,
        prep_time_minutes: 10,
        cook_time_minutes: 30
      })

    PlanningHandler.assign_recipe(ctx.plan_stream_id, "tue_dinner", recipe.id, 4)

    capsule = Capsule.build(ctx)
    assert length(capsule.slots) == 7
    [mon, tue | _] = capsule.slots
    assert mon.day == "Monday"
    assert mon.status == :empty
    assert tue.day == "Tuesday"
    assert tue.status == :assigned
  end

  test "to_prompt/1 renders the dinner plan with one line per day" do
    week_start = ~D[2026-06-08]
    ctx = ctx_for(week_start)

    prompt = ctx |> Capsule.build() |> Capsule.to_prompt()
    assert prompt =~ "This week's dinner plan:"
    assert prompt =~ "Monday 2026-06-08: empty"
    assert prompt =~ "Sunday 2026-06-14: empty"
  end

  test "to_prompt/1 is nil when the plan cannot be loaded" do
    bad_ctx = %{household_id: 1, plan_stream_id: nil, week_start: ~D[2026-06-08]}
    capsule = Capsule.build(bad_ctx)
    assert capsule.slots == nil
    assert Capsule.to_prompt(capsule) == nil
  end
end
