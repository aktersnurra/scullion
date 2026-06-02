defmodule Tore.Harness.Run.EventsTest do
  use ExUnit.Case, async: true
  alias Tore.Harness.Run.Events

  test "Opened carries stream_id, household_id, kind, surface, started_by, user_id, input, opened_at" do
    now = DateTime.utc_now()
    e = %Events.Opened{
      stream_id: "run-abc",
      household_id: 1,
      kind: "planner_command_run",
      surface: :plan,
      started_by: "user",
      user_id: 42,
      input: %{command: "skip mon dinner"},
      opened_at: now
    }
    assert e.stream_id == "run-abc"
    assert e.opened_at == now
  end

  test "PhaseEntered carries phase + at" do
    e = %Events.PhaseEntered{phase: :proposing, at: ~U[2026-06-02 12:00:00Z]}
    assert e.phase == :proposing
  end

  test "ToolStepRecorded carries step_index, step_kind, payload, ai_operation_id" do
    e = %Events.ToolStepRecorded{
      step_index: 0,
      step_kind: :tool_calls,
      payload: %{calls: []},
      ai_operation_id: 7
    }
    assert e.step_kind == :tool_calls
  end

  test "ArtifactAdded carries artifact" do
    art = %{__struct__: SomeArtifact, foo: :bar}
    e = %Events.ArtifactAdded{artifact: art}
    assert e.artifact == art
  end

  test "ModelUsageObserved carries prompt_tokens, completion_tokens, cost_usd" do
    e = %Events.ModelUsageObserved{
      prompt_tokens: 100,
      completion_tokens: 50,
      cost_usd: Decimal.new("0.0012")
    }
    assert e.prompt_tokens == 100
  end

  test "QuestionRaised and QuestionAnswered carry question/answer + at" do
    now = ~U[2026-06-02 12:00:00Z]
    assert %Events.QuestionRaised{question: "Which one?", at: now}.question == "Which one?"
    assert %Events.QuestionAnswered{answer: "the first", at: now}.answer == "the first"
  end

  test "Committed carries at" do
    e = %Events.Committed{at: ~U[2026-06-02 12:00:00Z]}
    assert e.at
  end

  test "FailureRecorded carries code, user_message, repair_action, at" do
    e = %Events.FailureRecorded{
      code: :slot_locked,
      user_message: "Slot is pinned",
      repair_action: nil,
      at: ~U[2026-06-02 12:00:00Z]
    }
    assert e.code == :slot_locked
  end

  test "Reverted carries at" do
    e = %Events.Reverted{at: ~U[2026-06-02 12:00:00Z]}
    assert e.at
  end
end
