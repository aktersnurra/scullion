defmodule Tore.Harness.Run.Decider do
  alias Tore.Harness.Run.{Commands, Events, State}
  alias Tore.Harness.Artifact

  @spec initial(String.t()) :: State.Draft.t()
  def initial(stream_id), do: %State.Draft{stream_id: stream_id}

  @spec decide(Commands.t(), State.t()) :: {:ok, [Events.t()]} | {:error, term()}

  def decide(%Commands.Open{} = c, %State.Draft{stream_id: sid}) do
    {:ok,
     [
       %Events.Opened{
         stream_id: sid,
         household_id: c.household_id,
         kind: c.kind,
         surface: c.surface,
         started_by: c.started_by,
         user_id: c.user_id,
         input: c.input,
         opened_at: DateTime.utc_now()
       }
     ]}
  end

  def decide(%Commands.EnterPhase{phase: p}, %State.Running{phase: p}), do: {:ok, []}

  def decide(%Commands.EnterPhase{phase: p}, %State.Running{}),
    do: {:ok, [%Events.PhaseEntered{phase: p, at: DateTime.utc_now()}]}

  def decide(%Commands.RecordToolStep{} = c, %State.Running{}) do
    {:ok,
     [
       %Events.ToolStepRecorded{
         step_index: c.step_index,
         step_kind: c.step_kind,
         payload: c.payload,
         ai_operation_id: c.ai_operation_id
       }
     ]}
  end

  def decide(%Commands.AddArtifact{artifact: a}, %State.Running{}) do
    if Artifact.is_rationale_complete(a) do
      {:ok, [%Events.ArtifactAdded{artifact: a}]}
    else
      {:error, :rationale_incomplete}
    end
  end

  def decide(%Commands.ObserveModelUsage{} = c, %State.Running{}) do
    {:ok,
     [
       %Events.ModelUsageObserved{
         prompt_tokens: c.prompt_tokens,
         completion_tokens: c.completion_tokens,
         cost_usd: c.cost_usd
       }
     ]}
  end

  def decide(%Commands.RaiseQuestion{question: q}, %State.Running{}),
    do: {:ok, [%Events.QuestionRaised{question: q, at: DateTime.utc_now()}]}

  def decide(%Commands.AnswerQuestion{answer: a}, %State.NeedsUser{}),
    do: {:ok, [%Events.QuestionAnswered{answer: a, at: DateTime.utc_now()}]}

  def decide(%Commands.Commit{undo_payload: payload}, %State.Running{}),
    do: {:ok, [%Events.Committed{at: DateTime.utc_now(), undo_payload: payload}]}

  def decide(%Commands.RecordFailure{} = c, %State.Running{}) do
    {:ok,
     [
       %Events.FailureRecorded{
         code: c.code,
         user_message: c.user_message,
         repair_action: c.repair_action,
         at: DateTime.utc_now()
       }
     ]}
  end

  def decide(%Commands.Revert{}, %State.Applied{}),
    do: {:ok, [%Events.Reverted{at: DateTime.utc_now()}]}

  # Discard is legal from NeedsUser (user-initiated) or Running (TTL sweep on
  # a run that never reached NeedsUser — defensive; the normal path is
  # NeedsUser-only).
  def decide(%Commands.Discard{reason: reason}, %State.NeedsUser{})
      when reason in [:user_discarded, :ttl_expired],
      do: {:ok, [%Events.RunDiscarded{reason: reason, at: DateTime.utc_now()}]}

  def decide(%Commands.Discard{reason: reason}, %State.Running{})
      when reason in [:user_discarded, :ttl_expired],
      do: {:ok, [%Events.RunDiscarded{reason: reason, at: DateTime.utc_now()}]}

  def decide(command, state),
    do: {:error, {:invalid_for_state, command.__struct__, state.__struct__}}

  @spec evolve(State.t(), Events.t()) :: State.t()

  def evolve(%State.Draft{stream_id: sid}, %Events.Opened{} = e) do
    %State.Running{
      stream_id: sid,
      household_id: e.household_id,
      kind: e.kind,
      surface: e.surface,
      started_by: e.started_by,
      user_id: e.user_id,
      input: e.input,
      opened_at: e.opened_at,
      phase: :gathering_context,
      tool_trace: [],
      artifacts: [],
      model_usage: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: Decimal.new(0)}
    }
  end

  def evolve(%State.Running{} = s, %Events.PhaseEntered{phase: p}),
    do: %{s | phase: p}

  def evolve(%State.Running{tool_trace: t} = s, %Events.ToolStepRecorded{} = e),
    do: %{s | tool_trace: t ++ [step_entry(e)]}

  def evolve(%State.Running{artifacts: a} = s, %Events.ArtifactAdded{artifact: art}),
    do: %{s | artifacts: a ++ [art]}

  def evolve(%State.Running{model_usage: m} = s, %Events.ModelUsageObserved{} = e),
    do: %{
      s
      | model_usage: %{
          prompt_tokens: m.prompt_tokens + e.prompt_tokens,
          completion_tokens: m.completion_tokens + e.completion_tokens,
          cost_usd: Decimal.add(m.cost_usd, e.cost_usd)
        }
    }

  def evolve(%State.Running{} = s, %Events.QuestionRaised{question: q}),
    do: to_needs_user(s, q)

  def evolve(%State.NeedsUser{} = s, %Events.QuestionAnswered{}),
    do: to_running(s)

  def evolve(%State.Running{} = s, %Events.Committed{at: at, undo_payload: payload}),
    do: to_applied(s, at, payload)

  def evolve(%State.Running{} = s, %Events.FailureRecorded{} = e),
    do: to_failed(s, e)

  def evolve(%State.Applied{} = s, %Events.Reverted{at: at}),
    do: to_reverted(s, at)

  def evolve(%State.NeedsUser{} = s, %Events.RunDiscarded{} = e),
    do: to_discarded(s, e)

  def evolve(%State.Running{} = s, %Events.RunDiscarded{} = e),
    do: to_discarded(s, e)

  defp step_entry(%Events.ToolStepRecorded{} = e) do
    %{
      step_index: e.step_index,
      step_kind: e.step_kind,
      payload: e.payload,
      ai_operation_id: e.ai_operation_id
    }
  end

  defp to_needs_user(%State.Running{} = s, q) do
    %State.NeedsUser{
      stream_id: s.stream_id,
      household_id: s.household_id,
      kind: s.kind,
      surface: s.surface,
      started_by: s.started_by,
      user_id: s.user_id,
      input: s.input,
      opened_at: s.opened_at,
      question: q,
      tool_trace: s.tool_trace,
      artifacts: s.artifacts,
      model_usage: s.model_usage
    }
  end

  defp to_running(%State.NeedsUser{} = s) do
    %State.Running{
      stream_id: s.stream_id,
      household_id: s.household_id,
      kind: s.kind,
      surface: s.surface,
      started_by: s.started_by,
      user_id: s.user_id,
      input: s.input,
      opened_at: s.opened_at,
      phase: :proposing,
      tool_trace: s.tool_trace,
      artifacts: s.artifacts,
      model_usage: s.model_usage
    }
  end

  defp to_applied(%State.Running{} = s, at, undo_payload) do
    %State.Applied{
      stream_id: s.stream_id,
      household_id: s.household_id,
      kind: s.kind,
      surface: s.surface,
      started_by: s.started_by,
      user_id: s.user_id,
      input: s.input,
      opened_at: s.opened_at,
      committed_at: at,
      tool_trace: s.tool_trace,
      artifacts: s.artifacts,
      model_usage: s.model_usage,
      undo_payload: undo_payload
    }
  end

  defp to_failed(%State.Running{} = s, %Events.FailureRecorded{} = e) do
    %State.Failed{
      stream_id: s.stream_id,
      household_id: s.household_id,
      kind: s.kind,
      surface: s.surface,
      started_by: s.started_by,
      user_id: s.user_id,
      input: s.input,
      opened_at: s.opened_at,
      failed_at: e.at,
      failure_code: e.code,
      failure_user_message: e.user_message,
      failure_repair_action: e.repair_action,
      tool_trace: s.tool_trace,
      artifacts: s.artifacts,
      model_usage: s.model_usage
    }
  end

  defp to_reverted(%State.Applied{} = s, at) do
    %State.Reverted{
      stream_id: s.stream_id,
      household_id: s.household_id,
      kind: s.kind,
      surface: s.surface,
      started_by: s.started_by,
      user_id: s.user_id,
      input: s.input,
      opened_at: s.opened_at,
      reverted_at: at,
      tool_trace: s.tool_trace,
      artifacts: s.artifacts,
      model_usage: s.model_usage
    }
  end

  defp to_discarded(s, %Events.RunDiscarded{reason: reason, at: at}) do
    %State.Discarded{
      stream_id: s.stream_id,
      household_id: s.household_id,
      kind: s.kind,
      surface: s.surface,
      started_by: s.started_by,
      user_id: s.user_id,
      input: s.input,
      opened_at: s.opened_at,
      discarded_at: at,
      discard_reason: reason,
      tool_trace: s.tool_trace,
      artifacts: Map.get(s, :artifacts, []),
      model_usage:
        Map.get(s, :model_usage, %{
          prompt_tokens: 0,
          completion_tokens: 0,
          cost_usd: Decimal.new(0)
        })
    }
  end
end
