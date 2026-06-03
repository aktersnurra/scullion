defmodule Tore.Harness.Orchestrator do
  alias Tore.Harness.Run
  alias Tore.Harness.Run.{Commands, State}
  alias Tore.Harness.Artifact.{PlanDiff, RunSummary}
  alias Tore.AiOperations
  alias Tore.LLM.PlannerAgent

  @spec dispatch(atom(), map()) :: {:ok, State.t()} | {:error, term()}

  def dispatch(:planner_command_run, ctx) do
    stream_id = Run.next_stream_id()
    metadata = %{household_id: ctx.household_id}

    with {:ok, state} <- open_run(stream_id, ctx, metadata),
         {:ok, state} <- enter(state, :gathering_context, metadata),
         {:ok, state} <- enter(state, :proposing, metadata),
         {:ok, loop} <- PlannerAgent.run(system_prompt(), ctx.command, agent_ctx(ctx, stream_id), []),
         {:ok, state} <- absorb_loop(state, loop, metadata),
         {:ok, state} <- enter(state, :verifying, metadata),
         {:ok, state} <- close(state, loop, ctx, metadata) do
      {:ok, state}
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
    state = absorb_trace(state, loop, metadata)
    absorb_usage(state, loop, metadata)
  end

  defp absorb_trace(state, loop, metadata) do
    Enum.reduce(loop.tool_trace, state, fn entry, acc ->
      ai_op_id = log_ai_operation(acc.stream_id, entry)

      cmd = %Commands.RecordToolStep{
        step_index: entry.step_index,
        step_kind: entry.step_kind,
        payload: entry.payload,
        ai_operation_id: ai_op_id
      }

      {:ok, acc} = apply_command(acc.stream_id, cmd, acc, metadata)
      acc
    end)
  end

  defp absorb_usage(state, loop, metadata) do
    final_state =
      Enum.reduce(loop.usage_per_step, state, fn usage, acc ->
        cmd = %Commands.ObserveModelUsage{
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens,
          cost_usd: usage.cost_usd
        }

        {:ok, acc} = apply_command(acc.stream_id, cmd, acc, metadata)
        acc
      end)

    {:ok, final_state}
  end

  defp close(state, %{result: {:message, _}}, ctx, metadata) do
    plan_diff = build_plan_diff(ctx)
    {:ok, state} = apply_command(state.stream_id, %Commands.AddArtifact{artifact: plan_diff}, state, metadata)

    run_summary = RunSummary.from_artifacts([plan_diff], :applied)
    {:ok, state} = apply_command(state.stream_id, %Commands.AddArtifact{artifact: run_summary}, state, metadata)

    apply_command(state.stream_id, %Commands.Commit{}, state, metadata)
  end

  defp close(state, %{result: {:question, q}}, _ctx, metadata),
    do: apply_command(state.stream_id, %Commands.RaiseQuestion{question: q}, state, metadata)

  defp close(state, %{result: {:capped, _}}, ctx, metadata) do
    plan_diff = build_plan_diff(ctx)
    run_summary = RunSummary.from_artifacts([plan_diff], :applied)
    {:ok, state} = apply_command(state.stream_id, %Commands.AddArtifact{artifact: plan_diff}, state, metadata)
    {:ok, state} = apply_command(state.stream_id, %Commands.AddArtifact{artifact: run_summary}, state, metadata)
    apply_command(state.stream_id, %Commands.Commit{}, state, metadata)
  end

  defp apply_command(stream_id, command, state, metadata) do
    with {:ok, events} <- Run.decide(command, state),
         :ok <- Run.append(stream_id, events, metadata) do
      new_state = Enum.reduce(events, state, fn ev, acc -> Run.evolve(acc, ev) end)
      {:ok, new_state}
    end
  end

  defp build_plan_diff(ctx) do
    %PlanDiff{
      plan_stream_id: ctx.plan_stream_id,
      week_start: ctx.week_start,
      events: [
        %{
          slot_key: "run",
          event_type: "MealSkipped",
          payload: %{},
          rationale: ["planner command applied"]
        }
      ]
    }
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
    """
  end
end
