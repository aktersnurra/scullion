defmodule Tore.Harness.Orchestrator do
  alias Tore.Harness.Run
  alias Tore.Harness.Run.{Commands, State}
  alias Tore.Harness.Artifact.RunSummary
  alias Tore.Harness.PlanDiffBuilder
  alias Tore.AiOperations
  alias Tore.LLM.PlannerAgent

  @type dispatch_error :: {:step_failed, term()} | {:run_crashed, Exception.t()}

  @spec dispatch(atom(), map()) :: {:ok, State.t()} | {:error, dispatch_error()}

  def dispatch(:planner_command_run, ctx) do
    stream_id = Run.next_stream_id()
    metadata = %{household_id: ctx.household_id}

    result =
      try do
        with {:ok, state} <- open_run(stream_id, ctx, metadata),
             {:ok, state} <- enter(state, :gathering_context, metadata),
             {:ok, state} <- enter(state, :proposing, metadata),
             {:ok, loop} <- PlannerAgent.run(system_prompt(), ctx.command, agent_ctx(ctx, stream_id), []),
             {:ok, state} <- absorb_loop(state, loop, metadata),
             {:ok, state} <- enter(state, :verifying, metadata),
             {:ok, state} <- close(state, loop, ctx, metadata) do
          {:ok, state}
        else
          {:error, reason} -> {:error, {:step_failed, reason}}
        end
      rescue
        e -> {:error, {:run_crashed, e}}
      end

    case result do
      {:ok, state} ->
        {:ok, state}

      {:error, _} = err ->
        record_failure(stream_id, metadata)
        err
    end
  end

  defp open_run(sid, ctx, metadata) do
    cmd = %Commands.Open{
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

    apply_command(sid, cmd, %State.Draft{stream_id: sid}, metadata)
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

  defp close(state, %{result: {:message, _}} = loop, ctx, metadata) do
    plan_diff = PlanDiffBuilder.build(loop.tool_trace, ctx)
    run_summary = RunSummary.from_artifacts([plan_diff], :applied)

    with {:ok, state} <- apply_command(state.stream_id, %Commands.AddArtifact{artifact: plan_diff}, state, metadata),
         {:ok, state} <- apply_command(state.stream_id, %Commands.AddArtifact{artifact: run_summary}, state, metadata) do
      apply_command(state.stream_id, %Commands.Commit{}, state, metadata)
    end
  end

  defp close(state, %{result: {:question, q}}, _ctx, metadata),
    do: apply_command(state.stream_id, %Commands.RaiseQuestion{question: q}, state, metadata)

  defp close(state, %{result: {:capped, _}} = loop, ctx, metadata) do
    plan_diff = PlanDiffBuilder.build(loop.tool_trace, ctx)
    run_summary = RunSummary.from_artifacts([plan_diff], :applied)

    with {:ok, state} <- apply_command(state.stream_id, %Commands.AddArtifact{artifact: plan_diff}, state, metadata),
         {:ok, state} <- apply_command(state.stream_id, %Commands.AddArtifact{artifact: run_summary}, state, metadata) do
      apply_command(state.stream_id, %Commands.Commit{}, state, metadata)
    end
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

  defp system_prompt do
    agent_preamble() <> "\n\n" <> Tore.Chat.SystemPrompt.build()
  end

  defp agent_ctx(ctx, stream_id) do
    %{
      plan_id: ctx.plan_stream_id,
      week_start: ctx.week_start,
      household_id: ctx.household_id,
      run_stream_id: stream_id
    }
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
