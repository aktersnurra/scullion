defmodule Tore.Harness.Orchestrator do
  require Logger
  alias Tore.Harness.Run
  alias Tore.Harness.Run.{Commands, State}
  alias Tore.Harness.Artifact.RunSummary
  alias Tore.Harness.PlanDiffBuilder
  alias Tore.AiOperations
  alias Tore.LLM.PlannerAgent
  alias Tore.Handlers.PlanningHandler
  alias Tore.Harness.Verifier.PlanVerifier
  alias Tore.Harness.Capsules

  alias Tore.Harness.Capsules.{
    HouseholdPreferencesCapsule,
    ActiveInsightsCapsule,
    WeekPlanCapsule,
    PantryBeliefsCapsule
  }

  @planner_capsules [
    HouseholdPreferencesCapsule,
    ActiveInsightsCapsule,
    WeekPlanCapsule,
    PantryBeliefsCapsule
  ]

  @type dispatch_error :: {:step_failed, term()} | {:run_crashed, Exception.t()}

  @spec dispatch(atom(), map()) :: {:ok, State.t()} | {:error, dispatch_error()}

  def dispatch(:planner_command_run, ctx) do
    stream_id = Run.next_stream_id()
    metadata = %{household_id: ctx.household_id}

    open_cmd = %Commands.Open{
      household_id: ctx.household_id,
      kind: "planner_command_run",
      surface: :plan,
      started_by: "user",
      user_id: ctx.user_id,
      input: %{
        command: ctx.command,
        plan_stream_id: ctx.plan_stream_id,
        week_start: ctx.week_start
      }
    }

    run_dispatch(stream_id, metadata, "planner_command_run", fn ->
      with {:ok, state} <- open_run(stream_id, open_cmd, metadata),
           {:ok, state} <- enter(state, :gathering_context, metadata),
           {:ok, state} <- enter(state, :proposing, metadata),
           {:ok, state} <-
             run_planner_loop(state, ctx, stream_id, ctx.command, [], metadata) do
        {:ok, state}
      else
        {:error, reason} -> {:error, {:step_failed, reason}}
      end
    end)
  end

  @weekly_max_round_trips 10
  @weekly_max_action_calls 25

  def dispatch(:weekly_planning_run, ctx) do
    stream_id = Run.next_stream_id()
    metadata = %{household_id: ctx.household_id}

    open_cmd = %Commands.Open{
      household_id: ctx.household_id,
      kind: "weekly_planning_run",
      surface: :plan,
      started_by: "system",
      user_id: ctx.user_id,
      input: %{
        plan_stream_id: ctx.plan_stream_id,
        week_start: ctx.week_start
      }
    }

    opts = [max_round_trips: @weekly_max_round_trips, max_action_calls: @weekly_max_action_calls]

    run_dispatch(stream_id, metadata, "weekly_planning_run", fn ->
      with {:ok, state} <- open_run(stream_id, open_cmd, metadata),
           {:ok, state} <- enter(state, :gathering_context, metadata),
           {:ok, state} <- enter(state, :proposing, metadata),
           {:ok, state} <-
             run_planner_loop(state, ctx, stream_id, weekly_fill_instruction(), opts, metadata) do
        {:ok, state}
      else
        {:error, reason} -> {:error, {:step_failed, reason}}
      end
    end)
  end

  defp open_run(sid, %Commands.Open{} = cmd, metadata) do
    apply_command(sid, cmd, %State.Draft{stream_id: sid}, metadata)
  end

  defp run_dispatch(stream_id, metadata, kind, fun) do
    result =
      try do
        fun.()
      rescue
        e ->
          Logger.error("#{kind} crashed: " <> Exception.format(:error, e, __STACKTRACE__))

          {:error, {:run_crashed, e}}
      end

    case result do
      {:ok, state} ->
        {:ok, state}

      {:error, _} = err ->
        record_failure(stream_id, metadata)
        err
    end
  end

  defp run_planner_loop(state, ctx, stream_id, user_text, opts, metadata) do
    with {:ok, working_plan} <- PlanningHandler.load_plan(ctx.plan_stream_id),
         {:ok, loop} <-
           PlannerAgent.run(
             system_prompt(ctx),
             user_text,
             agent_ctx(ctx, stream_id, working_plan),
             opts
           ),
         {:ok, state} <- absorb_loop(state, loop, metadata),
         {:ok, state} <- enter(state, :verifying, metadata),
         {:ok, state} <- close(state, loop, ctx, metadata) do
      {:ok, state}
    end
  end

  defp enter(state, phase, metadata),
    do: apply_command(state.stream_id, %Commands.EnterPhase{phase: phase}, state, metadata)

  defp absorb_loop(state, loop, metadata) do
    with {:ok, state} <- absorb_trace(state, loop, metadata) do
      absorb_usage(state, loop, metadata)
    end
  end

  defp absorb_trace(state, loop, metadata) do
    Enum.reduce_while(loop.tool_trace, {:ok, state}, fn entry, {:ok, acc} ->
      ai_op_id = log_ai_operation(acc.stream_id, entry)

      cmd = %Commands.RecordToolStep{
        step_index: entry.step_index,
        step_kind: entry.step_kind,
        payload: entry.payload,
        ai_operation_id: ai_op_id
      }

      case apply_command(acc.stream_id, cmd, acc, metadata) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp absorb_usage(state, loop, metadata) do
    Enum.reduce_while(loop.usage_per_step, {:ok, state}, fn usage, {:ok, acc} ->
      cmd = %Commands.ObserveModelUsage{
        prompt_tokens: usage.prompt_tokens,
        completion_tokens: usage.completion_tokens,
        cost_usd: usage.cost_usd
      }

      case apply_command(acc.stream_id, cmd, acc, metadata) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp close(state, %{result: {:message, _}} = loop, ctx, metadata),
    do: verify_and_finish(state, loop, ctx, metadata)

  defp close(state, %{result: {:capped, _}} = loop, ctx, metadata),
    do: verify_and_finish(state, loop, ctx, metadata)

  defp close(state, %{result: {:question, q}}, _ctx, metadata),
    do: apply_command(state.stream_id, %Commands.RaiseQuestion{question: q}, state, metadata)

  defp verify_and_finish(state, loop, ctx, metadata) do
    plan_diff = PlanDiffBuilder.build(loop.tool_trace, ctx)

    case PlanVerifier.verify(plan_diff, verify_ctx(loop)) do
      :ok ->
        run_summary = RunSummary.from_artifacts([plan_diff], :applied)

        with :ok <- PlanningHandler.apply_events(ctx.plan_stream_id, loop.plan_events),
             {:ok, state} <-
               apply_command(
                 state.stream_id,
                 %Commands.AddArtifact{artifact: plan_diff},
                 state,
                 metadata
               ),
             {:ok, state} <-
               apply_command(
                 state.stream_id,
                 %Commands.AddArtifact{artifact: run_summary},
                 state,
                 metadata
               ) do
          apply_command(state.stream_id, %Commands.Commit{}, state, metadata)
        end

      {:fail, code, repair} ->
        apply_command(
          state.stream_id,
          %Commands.RecordFailure{code: code, user_message: nil, repair_action: repair},
          state,
          metadata
        )
    end
  end

  defp verify_ctx(loop) do
    %{plan_state: loop.working_plan, preferences: Tore.Household.get_preferences()}
  end

  # On any dispatch failure, close the run as Failed so it isn't a dangling open
  # run the Projector replays forever. Only valid from Running (the Decider
  # rejects RecordFailure otherwise); a pre-Running failure persisted nothing to
  # close. Best-effort: a further append error is swallowed.
  defp record_failure(stream_id, metadata) do
    case Run.load(stream_id) do
      {:ok, %State.Running{} = state} ->
        cmd = %Commands.RecordFailure{
          code: :internal_error,
          user_message: nil,
          repair_action: nil
        }

        _ = apply_command(stream_id, cmd, state, metadata)
        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp apply_command(stream_id, command, state, metadata) do
    with {:ok, events} <- Run.decide(command, state),
         :ok <- Run.append(stream_id, events, metadata) do
      new_state = Enum.reduce(events, state, fn ev, acc -> Run.evolve(acc, ev) end)
      {:ok, new_state}
    end
  end

  defp log_ai_operation(stream_id, entry) do
    {:ok, op} =
      AiOperations.log(%{
        run_stream_id: stream_id,
        kind: "planner_agent." <> Atom.to_string(entry.step_kind),
        step_index: entry.step_index,
        payload: Jason.encode!(entry.payload),
        result: ""
      })

    op.id
  end

  defp system_prompt(ctx) do
    [
      agent_preamble(),
      date_line(),
      week_mode_line(),
      Capsules.compose(@planner_capsules, capsule_ctx(ctx))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp date_line do
    "Today is #{Calendar.strftime(Date.utc_today(), "%A, %B %-d, %Y")}."
  end

  defp week_mode_line do
    case Tore.WeekMode.mode_prompt_fragment(Tore.WeekMode.get_current_mode()) do
      nil -> nil
      fragment -> "Current week mode: #{fragment}"
    end
  end

  defp capsule_ctx(ctx) do
    %{
      household_id: ctx.household_id,
      plan_stream_id: ctx.plan_stream_id,
      week_start: ctx.week_start
    }
  end

  defp agent_ctx(ctx, stream_id, working_plan) do
    %{
      plan_id: ctx.plan_stream_id,
      week_start: ctx.week_start,
      household_id: ctx.household_id,
      run_stream_id: stream_id,
      working_plan: working_plan
    }
  end

  defp weekly_fill_instruction do
    """
    Fill every empty, unplanned dinner this week with a suitable recipe. Leave
    days that already have a meal, and days the household has pinned, exactly as
    they are. Use leftovers across days where it makes sense. When you are done,
    stop.
    """
  end

  defp agent_preamble do
    """
    You are the planner agent for Tore, a household meal planner.

    You operate by calling tools, not by replying in prose. When the user makes
    a request that maps to a planning action (assign, swap, skip, mark as
    leftovers, set servings, remove), call the corresponding tool. When you
    need to look up recipes, pantry, or deals to decide what to do, call the
    matching read tool first. When the user's request is ambiguous, call
    ask_user with a specific clarifying question instead of guessing.

    After your tool calls succeed, give a one-sentence confirmation of what you
    did. Do not narrate or restate the plan. If you cannot perform the action
    (a tool returned an error), explain what went wrong in one sentence.

    Always prefer calling a tool over describing what you would do.
    When you call an action tool, always include a short `rationale` saying why.
    """
  end
end
