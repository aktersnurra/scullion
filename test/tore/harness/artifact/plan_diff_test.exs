defmodule Tore.Harness.Artifact.PlanDiffTest do
  use ExUnit.Case, async: true
  alias Tore.Harness.Artifact.PlanDiff

  defp ev(slot, type, payload \\ %{}, rationale \\ ["because"]) do
    %{slot_key: slot, event_type: type, payload: payload, rationale: rationale}
  end

  test "kind/0" do
    assert PlanDiff.kind() == "PlanDiff"
  end

  test "enforce_keys: requires plan_stream_id, week_start, events" do
    assert_raise ArgumentError, fn -> struct!(PlanDiff, %{}) end
  end

  test "summarise/1: single MealSkipped event yields :skipped rollup" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("mon_dinner", "MealSkipped")]
    }
    [entry] = PlanDiff.summarise(diff)
    assert entry.slot_key == "mon_dinner"
    assert entry.change == :skipped
    assert entry.rationale == ["because"]
  end

  test "summarise/1: RecipeRemoved then RecipeAssigned collapses to :swapped" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [
        ev("mon_dinner", "RecipeRemoved", %{}, ["wrong recipe"]),
        ev("mon_dinner", "RecipeAssigned", %{"recipe_id" => 5, "label" => "Pasta"}, ["preferred"])
      ]
    }
    [entry] = PlanDiff.summarise(diff)
    assert entry.change == :swapped
    assert entry.label == "Pasta"
    assert entry.rationale == ["wrong recipe", "preferred"]
  end

  test "summarise/1: RecipeAssigned alone yields :added" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("tue_dinner", "RecipeAssigned", %{"label" => "Stew"})]
    }
    [entry] = PlanDiff.summarise(diff)
    assert entry.change == :added
    assert entry.label == "Stew"
  end

  test "summarise/1: LeftoverMarked yields :leftover" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("wed_dinner", "LeftoverMarked")]
    }
    [entry] = PlanDiff.summarise(diff)
    assert entry.change == :leftover
  end

  test "summarise/1: RecipeRemoved alone yields :removed" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("thu_dinner", "RecipeRemoved")]
    }
    [entry] = PlanDiff.summarise(diff)
    assert entry.change == :removed
  end

  test "summary/1: counts and text fallback" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [
        ev("mon", "MealSkipped"),
        ev("tue", "RecipeAssigned", %{"label" => "x"}),
        ev("wed", "RecipeAssigned", %{"label" => "y"})
      ]
    }
    s = PlanDiff.summary(diff)
    assert s.counts == %{skipped: 1, added: 2}
    assert s.text_fallback =~ "skipped"
    assert s.text_fallback =~ "added"
  end

  test "is_rationale_complete/1: false when any event has empty rationale" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("mon", "MealSkipped", %{}, [])]
    }
    refute PlanDiff.is_rationale_complete(diff)
  end

  test "is_rationale_complete/1: true when all events have rationale" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("mon", "MealSkipped", %{}, ["why"])]
    }
    assert PlanDiff.is_rationale_complete(diff)
  end

  test "to_json/1 and from_json/1 round-trip" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1",
      week_start: ~D[2026-06-01],
      events: [ev("mon", "MealSkipped")]
    }
    encoded = PlanDiff.to_json(diff)
    decoded = PlanDiff.from_json(encoded)
    assert decoded.plan_stream_id == "plan-1"
    assert decoded.week_start == ~D[2026-06-01]
    assert length(decoded.events) == 1
  end
end
