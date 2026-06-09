defmodule Tore.Harness.Run.StateTest do
  use ExUnit.Case, async: true
  alias Tore.Harness.Run.State

  test "empty/1 returns a Draft with the given stream_id" do
    assert %State.Draft{stream_id: "run-abc"} = State.empty("run-abc")
  end

  test "Draft enforces stream_id" do
    assert_raise ArgumentError, fn ->
      struct!(State.Draft, %{})
    end
  end

  test "Running enforces its 12 keys" do
    assert_raise ArgumentError, fn ->
      struct!(State.Running, %{stream_id: "x"})
    end
  end

  test "Running constructs when all keys present" do
    s = %State.Running{
      stream_id: "x",
      household_id: 1,
      kind: "planner_command_run",
      surface: :plan,
      started_by: "user",
      user_id: 1,
      input: %{},
      opened_at: ~U[2026-06-02 12:00:00Z],
      phase: :gathering_context,
      tool_trace: [],
      artifacts: [],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }

    assert s.phase == :gathering_context
  end

  test "Failed enforces failure_user_message" do
    assert_raise ArgumentError, fn ->
      struct!(State.Failed, %{
        stream_id: "x",
        household_id: 1,
        kind: "k",
        surface: :plan,
        started_by: "user",
        user_id: 1,
        input: %{},
        opened_at: ~U[2026-06-02 12:00:00Z],
        failed_at: ~U[2026-06-02 12:00:00Z],
        failure_code: :x,
        # failure_user_message missing
        failure_repair_action: nil,
        tool_trace: [],
        artifacts: [],
        model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
      })
    end
  end

  test "NeedsUser, Applied, Reverted each enforce their key sets" do
    assert_raise ArgumentError, fn -> struct!(State.NeedsUser, %{stream_id: "x"}) end
    assert_raise ArgumentError, fn -> struct!(State.Applied, %{stream_id: "x"}) end
    assert_raise ArgumentError, fn -> struct!(State.Reverted, %{stream_id: "x"}) end
  end
end
