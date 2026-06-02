defmodule Tore.Harness.Artifact.RunSummaryTest do
  use ExUnit.Case, async: true
  alias Tore.Harness.Artifact.{PlanDiff, RunSummary}

  test "kind/0" do
    assert RunSummary.kind() == "RunSummary"
  end

  test "enforce_keys: counts and outcome" do
    assert_raise ArgumentError, fn -> struct!(RunSummary, %{}) end
  end

  test "from_artifacts/2: aggregates PlanDiff counts into RunSummary" do
    diff = %PlanDiff{
      plan_stream_id: "p", week_start: ~D[2026-06-01],
      events: [
        %{slot_key: "mon", event_type: "MealSkipped", payload: %{}, rationale: ["x"]},
        %{slot_key: "tue", event_type: "RecipeAssigned", payload: %{}, rationale: ["x"]}
      ]
    }
    s = RunSummary.from_artifacts([diff], :applied)
    assert s.outcome == :applied
    assert s.counts == %{skipped: 1, added: 1}
  end

  test "from_artifacts/2: with outcome :needs_user" do
    s = RunSummary.from_artifacts([], :needs_user)
    assert s.outcome == :needs_user
    assert s.counts == %{}
  end

  test "summary/1: returns counts and text_fallback" do
    s = %RunSummary{counts: %{added: 2, skipped: 1}, outcome: :applied}
    out = RunSummary.summary(s)
    assert out.counts == %{added: 2, skipped: 1}
    assert is_binary(out.text_fallback)
  end

  test "is_rationale_complete/1: always true" do
    assert RunSummary.is_rationale_complete(%RunSummary{counts: %{}, outcome: :applied})
  end

  test "to_json/1 and from_json/1 round-trip" do
    s = %RunSummary{counts: %{added: 2, skipped: 1}, outcome: :applied}
    decoded = RunSummary.from_json(RunSummary.to_json(s))
    assert decoded.outcome == :applied
    assert decoded.counts == %{added: 2, skipped: 1}
  end
end
