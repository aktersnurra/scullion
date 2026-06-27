defmodule Tore.Harness.Run.DeciderTest do
  use ExUnit.Case, async: true
  alias Tore.Harness.Run.{Commands, Events, State, Decider}

  defp opened_state do
    {:ok, [opened]} =
      Decider.decide(
        %Commands.Open{
          household_id: 1,
          kind: "planner_command_run",
          surface: :plan,
          started_by: "user",
          user_id: 42,
          input: %{command: "x"}
        },
        %State.Draft{stream_id: "run-abc"}
      )

    Decider.evolve(%State.Draft{stream_id: "run-abc"}, opened)
  end

  describe "decide/2 — Open" do
    test "Draft + Open produces Opened with stream_id from Draft" do
      {:ok, [event]} =
        Decider.decide(
          %Commands.Open{
            household_id: 1,
            kind: "planner_command_run",
            surface: :plan,
            started_by: "user",
            user_id: 42,
            input: %{command: "x"}
          },
          %State.Draft{stream_id: "run-abc"}
        )

      assert event.stream_id == "run-abc"
      assert event.household_id == 1
      assert event.kind == "planner_command_run"
      assert %DateTime{} = event.opened_at
    end

    test "Running + Open is invalid" do
      assert {:error, {:invalid_for_state, Commands.Open, State.Running}} =
               Decider.decide(
                 %Commands.Open{
                   household_id: 1,
                   kind: "k",
                   surface: :plan,
                   started_by: "user",
                   user_id: 1,
                   input: %{}
                 },
                 opened_state()
               )
    end
  end

  describe "decide/2 — phases" do
    test "EnterPhase to same phase produces no events" do
      s = opened_state()
      assert {:ok, []} = Decider.decide(%Commands.EnterPhase{phase: :gathering_context}, s)
    end

    test "EnterPhase to new phase produces PhaseEntered" do
      s = opened_state()
      {:ok, [e]} = Decider.decide(%Commands.EnterPhase{phase: :proposing}, s)
      assert %Events.PhaseEntered{phase: :proposing} = e
    end
  end

  describe "decide/2 — tool steps and usage" do
    test "RecordToolStep produces ToolStepRecorded with carried fields" do
      s = opened_state()

      cmd = %Commands.RecordToolStep{
        step_index: 3,
        step_kind: :tool_calls,
        payload: %{x: 1},
        ai_operation_id: 9
      }

      {:ok, [e]} = Decider.decide(cmd, s)

      assert %Events.ToolStepRecorded{
               step_index: 3,
               step_kind: :tool_calls,
               payload: %{x: 1},
               ai_operation_id: 9
             } = e
    end

    test "ObserveModelUsage produces ModelUsageObserved" do
      s = opened_state()

      cmd = %Commands.ObserveModelUsage{
        prompt_tokens: 10,
        completion_tokens: 5,
        cost_usd: Decimal.new("0.001")
      }

      {:ok, [e]} = Decider.decide(cmd, s)
      assert %Events.ModelUsageObserved{prompt_tokens: 10} = e
    end
  end

  describe "decide/2 — questions and commit" do
    test "RaiseQuestion in Running produces QuestionRaised" do
      s = opened_state()
      {:ok, [e]} = Decider.decide(%Commands.RaiseQuestion{question: "which?"}, s)
      assert %Events.QuestionRaised{question: "which?"} = e
    end

    test "AnswerQuestion in NeedsUser produces QuestionAnswered" do
      s = opened_state()
      {:ok, [raised]} = Decider.decide(%Commands.RaiseQuestion{question: "q"}, s)
      needs = Decider.evolve(s, raised)
      {:ok, [e]} = Decider.decide(%Commands.AnswerQuestion{answer: "a"}, needs)
      assert %Events.QuestionAnswered{answer: "a"} = e
    end

    test "AnswerQuestion in Running is invalid" do
      s = opened_state()

      assert {:error, {:invalid_for_state, Commands.AnswerQuestion, State.Running}} =
               Decider.decide(%Commands.AnswerQuestion{answer: "a"}, s)
    end

    test "Commit in Running produces Committed" do
      s = opened_state()
      {:ok, [e]} = Decider.decide(%Commands.Commit{}, s)
      assert %Events.Committed{} = e
    end

    test "Commit in Running propagates undo_payload onto the Committed event" do
      s = opened_state()
      payload = %Tore.Harness.UndoPayload{kind: :irreversible, data: %{reason: "test"}}
      {:ok, [e]} = Decider.decide(%Commands.Commit{undo_payload: payload}, s)
      assert %Events.Committed{undo_payload: ^payload} = e
    end

    test "Commit in Draft is invalid" do
      assert {:error, {:invalid_for_state, Commands.Commit, State.Draft}} =
               Decider.decide(%Commands.Commit{}, %State.Draft{stream_id: "x"})
    end
  end

  describe "decide/2 — failure and revert" do
    test "RecordFailure in Running produces FailureRecorded" do
      s = opened_state()

      cmd = %Commands.RecordFailure{
        code: :slot_locked,
        user_message: "Locked",
        repair_action: nil
      }

      {:ok, [e]} = Decider.decide(cmd, s)
      assert %Events.FailureRecorded{code: :slot_locked, user_message: "Locked"} = e
    end

    test "Revert in Applied produces Reverted" do
      s = opened_state()
      {:ok, [committed]} = Decider.decide(%Commands.Commit{}, s)
      applied = Decider.evolve(s, committed)
      {:ok, [e]} = Decider.decide(%Commands.Revert{}, applied)
      assert %Events.Reverted{} = e
    end
  end

  describe "evolve/2 — folding" do
    test "Draft + Opened transitions to Running with empty trace/artifacts/usage" do
      d = %State.Draft{stream_id: "run-abc"}

      e = %Events.Opened{
        stream_id: "run-abc",
        household_id: 1,
        kind: "planner_command_run",
        surface: :plan,
        started_by: "user",
        user_id: 42,
        input: %{command: "x"},
        opened_at: ~U[2026-06-02 12:00:00Z]
      }

      r = Decider.evolve(d, e)
      assert %State.Running{phase: :gathering_context, tool_trace: [], artifacts: []} = r
      assert r.model_usage == %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    end

    test "Running + ToolStepRecorded appends to tool_trace" do
      s = opened_state()

      e = %Events.ToolStepRecorded{
        step_index: 0,
        step_kind: :message,
        payload: %{text: "ok"},
        ai_operation_id: 1
      }

      r = Decider.evolve(s, e)
      assert [%{step_index: 0, step_kind: :message}] = r.tool_trace
    end

    test "Running + ModelUsageObserved accumulates" do
      s = opened_state()

      s2 =
        Decider.evolve(s, %Events.ModelUsageObserved{
          prompt_tokens: 10,
          completion_tokens: 5,
          cost_usd: Decimal.new("0.001")
        })

      s3 =
        Decider.evolve(s2, %Events.ModelUsageObserved{
          prompt_tokens: 7,
          completion_tokens: 3,
          cost_usd: Decimal.new("0.002")
        })

      assert s3.model_usage.prompt_tokens == 17
      assert s3.model_usage.completion_tokens == 8
      assert Decimal.equal?(s3.model_usage.cost_usd, Decimal.new("0.003"))
    end

    test "Running + Committed transitions to Applied with committed_at" do
      s = opened_state()
      at = ~U[2026-06-02 13:00:00Z]
      applied = Decider.evolve(s, %Events.Committed{at: at})
      assert %State.Applied{committed_at: ^at} = applied
    end

    test "Running + Committed carries undo_payload through to Applied" do
      s = opened_state()
      payload = %Tore.Harness.UndoPayload{kind: :irreversible, data: %{reason: "test"}}

      applied =
        Decider.evolve(s, %Events.Committed{at: ~U[2026-06-02 13:00:00Z], undo_payload: payload})

      assert %State.Applied{undo_payload: ^payload} = applied
    end

    test "Running + FailureRecorded transitions to Failed with code/message/repair" do
      s = opened_state()
      at = ~U[2026-06-02 13:00:00Z]

      e = %Events.FailureRecorded{
        code: :slot_locked,
        user_message: "Locked",
        repair_action: nil,
        at: at
      }

      failed = Decider.evolve(s, e)

      assert %State.Failed{
               failed_at: ^at,
               failure_code: :slot_locked,
               failure_user_message: "Locked"
             } = failed
    end

    test "Running + QuestionRaised transitions to NeedsUser carrying question" do
      s = opened_state()

      needs =
        Decider.evolve(s, %Events.QuestionRaised{question: "which?", at: ~U[2026-06-02 12:00:00Z]})

      assert %State.NeedsUser{question: "which?"} = needs
    end

    test "NeedsUser + QuestionAnswered transitions back to Running" do
      s = opened_state()

      needs =
        Decider.evolve(s, %Events.QuestionRaised{question: "q", at: ~U[2026-06-02 12:00:00Z]})

      running =
        Decider.evolve(needs, %Events.QuestionAnswered{answer: "a", at: ~U[2026-06-02 12:00:01Z]})

      assert %State.Running{} = running
    end

    test "Applied + Reverted transitions to Reverted" do
      s = opened_state()
      applied = Decider.evolve(s, %Events.Committed{at: ~U[2026-06-02 13:00:00Z]})
      reverted = Decider.evolve(applied, %Events.Reverted{at: ~U[2026-06-02 13:05:00Z]})
      assert %State.Reverted{reverted_at: ~U[2026-06-02 13:05:00Z]} = reverted
    end
  end
end
