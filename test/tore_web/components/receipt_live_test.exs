defmodule ToreWeb.Components.ReceiptLiveTest do
  use ToreWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias ToreWeb.Components.ReceiptLive
  alias Tore.Harness.Run.State
  alias Tore.Harness.Artifact.{PlanDiff, RunSummary}

  defp base_running do
    %State.Running{
      stream_id: "run-x", household_id: 1, kind: "planner_command_run",
      surface: :plan, started_by: "user", user_id: 1,
      input: %{command: "x"},
      opened_at: ~U[2026-06-02 12:00:00Z],
      phase: :proposing,
      tool_trace: [], artifacts: [],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }
  end

  test "renders phase label for Running" do
    html = render_component(ReceiptLive, id: "r", run: base_running())
    assert html =~ "Proposing" or html =~ "proposing"
  end

  test "renders question for NeedsUser" do
    needs = %State.NeedsUser{
      stream_id: "run-x", household_id: 1, kind: "planner_command_run",
      surface: :plan, started_by: "user", user_id: 1, input: %{},
      opened_at: ~U[2026-06-02 12:00:00Z],
      question: "Which Monday?",
      tool_trace: [], artifacts: [],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }
    html = render_component(ReceiptLive, id: "r", run: needs)
    assert html =~ "Which Monday?"
  end

  test "renders summary for Applied with header text" do
    diff = %PlanDiff{
      plan_stream_id: "plan-1", week_start: ~D[2026-06-01],
      events: [%{slot_key: "mon", event_type: "MealSkipped", payload: %{}, rationale: ["x"]}]
    }
    rs = RunSummary.from_artifacts([diff], :applied)

    applied = %State.Applied{
      stream_id: "run-x", household_id: 1, kind: "planner_command_run",
      surface: :plan, started_by: "user", user_id: 1, input: %{},
      opened_at: ~U[2026-06-02 12:00:00Z],
      committed_at: ~U[2026-06-02 12:01:00Z],
      tool_trace: [], artifacts: [diff, rs],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }

    html = render_component(ReceiptLive, id: "r", run: applied)
    assert html =~ "Tore adjusted the plan"
    assert html =~ "skipped"
  end

  test "renders failure for Failed with header text and user message" do
    failed = %State.Failed{
      stream_id: "run-x", household_id: 1, kind: "planner_command_run",
      surface: :plan, started_by: "user", user_id: 1, input: %{},
      opened_at: ~U[2026-06-02 12:00:00Z],
      failed_at: ~U[2026-06-02 12:00:01Z],
      failure_code: :slot_locked,
      failure_user_message: "That slot is pinned.",
      failure_repair_action: nil,
      tool_trace: [], artifacts: [],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }
    html = render_component(ReceiptLive, id: "r", run: failed)
    assert html =~ "couldn"
    assert html =~ "That slot is pinned."
  end

  test "renders quiet line for Reverted" do
    reverted = %State.Reverted{
      stream_id: "run-x", household_id: 1, kind: "planner_command_run",
      surface: :plan, started_by: "user", user_id: 1, input: %{},
      opened_at: ~U[2026-06-02 12:00:00Z],
      reverted_at: ~U[2026-06-02 12:01:00Z],
      tool_trace: [], artifacts: [],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }
    html = render_component(ReceiptLive, id: "r", run: reverted)
    assert html =~ "Reverted" or html =~ "reverted"
  end
end
