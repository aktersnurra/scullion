defmodule Tore.Harness.ProjectorTest do
  use Tore.DataCase, async: false
  alias Tore.Harness.{Projector, ProjectorSupervisor}
  alias Tore.Harness.Run
  alias Tore.Harness.Run.{Commands, State}

  setup do
    {:ok, pid} = ProjectorSupervisor.start_or_lookup(99)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    :ok
  end

  test "latest_on_surface/2 returns nil when no run has been opened" do
    assert Projector.latest_on_surface(99, :plan) == nil
  end

  test "latest_on_surface/2 reflects a newly opened run after PubSub broadcast" do
    sid = Run.next_stream_id()

    {:ok, [ev]} =
      Run.decide(
        %Commands.Open{
          household_id: 99,
          kind: "planner_command_run",
          surface: :plan,
          started_by: "user",
          user_id: 1,
          input: %{command: "x"}
        },
        %State.Draft{stream_id: sid}
      )

    :ok = Run.append(sid, [ev], %{household_id: 99})

    # Wait briefly for the projector to handle the broadcast.
    Process.sleep(50)
    state = Projector.latest_on_surface(99, :plan)
    assert %State.Running{stream_id: ^sid} = state
  end

  test "lookup/2 returns nil for an unknown stream_id" do
    assert Projector.lookup(99, "run-unknown") == nil
  end

  test "projector boots by replaying open runs only" do
    sid = Run.next_stream_id()

    {:ok, [ev]} =
      Run.decide(
        %Commands.Open{
          household_id: 100,
          kind: "planner_command_run",
          surface: :plan,
          started_by: "user",
          user_id: 1,
          input: %{}
        },
        %State.Draft{stream_id: sid}
      )

    :ok = Run.append(sid, [ev], %{household_id: 100})

    {:ok, _pid} = ProjectorSupervisor.start_or_lookup(100)
    Process.sleep(50)

    assert %State.Running{stream_id: ^sid} = Projector.latest_on_surface(100, :plan)
  end
end
