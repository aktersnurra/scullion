defmodule Tore.Harness.RunTest do
  use Tore.DataCase, async: false
  alias Tore.Harness.Run
  alias Tore.Harness.Run.{Commands, Events, State}

  test "next_stream_id/0 returns a string with 'run-' prefix" do
    id = Run.next_stream_id()
    assert "run-" <> _ = id
    assert String.length(id) > 6
  end

  test "load/1 returns Draft for an unknown stream_id" do
    {:ok, state} = Run.load("run-never-seen")
    assert %State.Draft{stream_id: "run-never-seen"} = state
  end

  test "append/3 persists events and load/1 replays them" do
    sid = Run.next_stream_id()
    {:ok, [opened]} =
      Run.decide(
        %Commands.Open{
          household_id: 1, kind: "planner_command_run", surface: :plan,
          started_by: "user", user_id: 1, input: %{command: "x"}
        },
        %State.Draft{stream_id: sid}
      )
    :ok = Run.append(sid, [opened])
    {:ok, state} = Run.load(sid)
    assert %State.Running{stream_id: ^sid, household_id: 1, kind: "planner_command_run"} = state
  end

  test "append/3 broadcasts {:run_event, stream_id, event} on the household topic" do
    sid = Run.next_stream_id()
    hh = 7
    Phoenix.PubSub.subscribe(Tore.PubSub, "harness:household:#{hh}")

    {:ok, [opened]} =
      Run.decide(
        %Commands.Open{
          household_id: hh, kind: "planner_command_run", surface: :plan,
          started_by: "user", user_id: 1, input: %{}
        },
        %State.Draft{stream_id: sid}
      )

    :ok = Run.append(sid, [opened], %{household_id: hh})
    assert_receive {:run_event, ^sid, %Events.Opened{household_id: ^hh}}, 500
  end

  test "decide/2 and evolve/2 delegate to Decider" do
    sid = Run.next_stream_id()
    assert function_exported?(Run, :decide, 2)
    assert function_exported?(Run, :evolve, 2)

    {:ok, [opened]} =
      Run.decide(
        %Commands.Open{
          household_id: 1, kind: "planner_command_run", surface: :plan,
          started_by: "user", user_id: 1, input: %{}
        },
        %State.Draft{stream_id: sid}
      )

    running = Run.evolve(%State.Draft{stream_id: sid}, opened)
    assert {:ok, []} = Run.decide(%Commands.EnterPhase{phase: :gathering_context}, running)
  end
end
