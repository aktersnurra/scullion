defmodule Tore.Harness.OrchestratorTest do
  use Tore.DataCase, async: false
  import Mox
  import Ecto.Query
  setup :verify_on_exit!

  alias Tore.Harness.{Orchestrator, Run}
  alias Tore.Harness.Run.State

  @ctx %{
    household_id: 1,
    user_id: 42,
    command: "skip mon dinner",
    plan_stream_id: "plan-1",
    week_start: ~D[2026-06-01]
  }

  test "dispatch(:planner_command_run, ctx) returns {:ok, %State.Applied{}} on a clean message run" do
    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok, {:message, "Skipped Monday dinner."},
       %{prompt_tokens: 10, completion_tokens: 3, cost_usd: Decimal.new("0.0001")}}
    end)

    assert {:ok, %State.Applied{} = state} = Orchestrator.dispatch(:planner_command_run, @ctx)
    assert state.kind == "planner_command_run"
    assert state.household_id == 1
  end

  test "dispatch persists a 'run' event stream that can be replayed" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "ok"},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    {:ok, state} = Orchestrator.dispatch(:planner_command_run, @ctx)
    {:ok, replayed} = Run.load(state.stream_id)
    sid = state.stream_id
    assert %State.Applied{stream_id: ^sid} = replayed
  end

  test "dispatch writes ai_operations rows tagged with the run's stream_id" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "done"},
       %{prompt_tokens: 5, completion_tokens: 2, cost_usd: Decimal.new("0.0001")}}
    end)

    {:ok, state} = Orchestrator.dispatch(:planner_command_run, @ctx)
    rows = Tore.AiOperations.list_for_run(state.stream_id)
    assert rows != []
    assert Enum.all?(rows, fn r -> r.run_stream_id == state.stream_id end)
  end

  test "dispatch returns NeedsUser when the agent invokes ask_user" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok,
       {:tool_calls, [%{id: "c1", name: "ask_user", args: %{"question" => "which Monday?"}}]},
       %{prompt_tokens: 4, completion_tokens: 2, cost_usd: Decimal.new(0)}}
    end)

    assert {:ok, %State.NeedsUser{question: "which Monday?"}} =
             Orchestrator.dispatch(:planner_command_run, @ctx)
  end

  test "dispatch builds a real PlanDiff from the planner's skip_meal call" do
    {:ok, recipe} = Tore.Recipes.create(%{title: "Chili", recipe_type: :meal, base_servings: 4})
    plan = "plan:2026-06-01"
    Tore.Handlers.PlanningHandler.assign_recipe(plan, "mon_dinner", recipe.id, 4)

    Mox.expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok,
       {:tool_calls,
        [%{id: "c1", name: "skip_meal",
           args: %{"slot_key" => "mon_dinner", "rationale" => "busy night"}}]},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    Mox.expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok, {:message, "Done."},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    ctx = %{household_id: 1, user_id: 1, command: "skip monday",
            plan_stream_id: plan, week_start: ~D[2026-06-01]}

    {:ok, state} = Tore.Harness.Orchestrator.dispatch(:planner_command_run, ctx)

    plan_diff = Enum.find(state.artifacts, &match?(%Tore.Harness.Artifact.PlanDiff{}, &1))
    assert [%{slot_key: "mon_dinner", event_type: "MealSkipped", rationale: ["busy night"]}] =
             plan_diff.events
    refute Enum.any?(plan_diff.events, &(&1.slot_key == "run"))
  end

  test "dispatch broadcasts run events on the household topic" do
    Phoenix.PubSub.subscribe(Tore.PubSub, "harness:household:1")

    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "ok"}, %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    {:ok, _state} = Orchestrator.dispatch(:planner_command_run, @ctx)

    assert_receive {:run_event, _sid, %Tore.Harness.Run.Events.Opened{}}, 1_000
    assert_receive {:run_event, _sid, %Tore.Harness.Run.Events.Committed{}}, 1_000
  end

  test "dispatch returns {:step_failed, reason} and records the run as Failed when a step errors" do
    Mox.stub(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:error, :boom}
    end)

    ctx = %{household_id: 1, user_id: 1, command: "skip monday",
            plan_stream_id: "plan:2026-06-01", week_start: ~D[2026-06-01]}

    assert {:error, {:step_failed, :boom}} = Tore.Harness.Orchestrator.dispatch(:planner_command_run, ctx)

    sid = latest_run_stream_id()
    assert {:ok, %Tore.Harness.Run.State.Failed{failure_code: :internal_error}} =
             Tore.Harness.Run.load(sid)
  end

  test "dispatch returns {:run_crashed, exception} and records Failed when a step raises" do
    Mox.stub(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      raise "boom"
    end)

    ctx = %{household_id: 1, user_id: 1, command: "skip monday",
            plan_stream_id: "plan:2026-06-01", week_start: ~D[2026-06-01]}

    assert {:error, {:run_crashed, %RuntimeError{message: "boom"}}} =
             Tore.Harness.Orchestrator.dispatch(:planner_command_run, ctx)

    sid = latest_run_stream_id()
    assert {:ok, %Tore.Harness.Run.State.Failed{}} = Tore.Harness.Run.load(sid)
  end

  test "dispatch applies accumulated plan events to the plan stream exactly once" do
    {:ok, recipe} = Tore.Recipes.create(%{title: "Stew", recipe_type: :meal, base_servings: 4})
    plan = "plan:2026-06-08-apply"
    Tore.Handlers.PlanningHandler.assign_recipe(plan, "mon_dinner", recipe.id, 4)

    Mox.expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:tool_calls, [%{id: "c1", name: "skip_meal", args: %{"slot_key" => "mon_dinner", "rationale" => "out"}}]},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    Mox.expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "Done."}, %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    ctx = %{household_id: 1, user_id: 1, command: "skip monday", plan_stream_id: plan, week_start: ~D[2026-06-08]}
    {:ok, %State.Applied{}} = Orchestrator.dispatch(:planner_command_run, ctx)

    {:ok, plan_state} = Tore.Handlers.PlanningHandler.load_plan(plan)
    assert plan_state.slots["mon_dinner"].skipped == true
  end

  test "a failed step leaves the plan stream unwritten (nothing applied)" do
    plan = "plan:2026-06-08-empty"
    Mox.stub(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ -> {:error, :boom} end)

    ctx = %{household_id: 1, user_id: 1, command: "skip monday", plan_stream_id: plan, week_start: ~D[2026-06-08]}
    assert {:error, {:step_failed, :boom}} = Orchestrator.dispatch(:planner_command_run, ctx)

    {:ok, plan_state} = Tore.Handlers.PlanningHandler.load_plan(plan)
    assert plan_state.slots == %{}
  end

  defp latest_run_stream_id do
    Tore.Repo.one(
      from e in Tore.EventStore.Event,
        where: e.stream_type == "run",
        order_by: [desc: e.id], limit: 1, select: e.stream_id
    )
  end
end
