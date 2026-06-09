defmodule Tore.Harness.Run.CommandsTest do
  use ExUnit.Case, async: true
  alias Tore.Harness.Run.Commands

  test "Open carries household_id, kind, surface, started_by, user_id, input" do
    c = %Commands.Open{
      household_id: 1,
      kind: "planner_command_run",
      surface: :plan,
      started_by: "user",
      user_id: 42,
      input: %{command: "x"}
    }

    assert c.kind == "planner_command_run"
  end

  test "all ten command structs construct" do
    assert %Commands.EnterPhase{phase: :proposing}.phase == :proposing

    assert %Commands.RecordToolStep{
             step_index: 0,
             step_kind: :tool_calls,
             payload: %{},
             ai_operation_id: 1
           }.step_kind == :tool_calls

    assert %Commands.AddArtifact{artifact: :stub}.artifact == :stub

    assert %Commands.ObserveModelUsage{
             prompt_tokens: 1,
             completion_tokens: 2,
             cost_usd: Decimal.new(0)
           }.prompt_tokens == 1

    assert %Commands.RaiseQuestion{question: "q"}.question == "q"
    assert %Commands.AnswerQuestion{answer: "a"}.answer == "a"
    assert %Commands.Commit{} == %Commands.Commit{}
    assert %Commands.RecordFailure{code: :x, user_message: "m", repair_action: nil}.code == :x
    assert %Commands.Revert{} == %Commands.Revert{}
  end
end
