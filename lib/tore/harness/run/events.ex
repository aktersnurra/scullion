defmodule Tore.Harness.Run.Events do
  defmodule Opened do
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at
    ]
  end

  defmodule PhaseEntered do
    defstruct [:phase, :at]
  end

  defmodule ToolStepRecorded do
    defstruct [:step_index, :step_kind, :payload, :ai_operation_id]
  end

  defmodule ArtifactAdded do
    defstruct [:artifact]
  end

  defmodule ModelUsageObserved do
    defstruct [:prompt_tokens, :completion_tokens, :cost_usd]
  end

  defmodule QuestionRaised do
    defstruct [:question, :at]
  end

  defmodule QuestionAnswered do
    defstruct [:answer, :at]
  end

  defmodule Committed do
    defstruct [:at, :undo_payload]
  end

  defmodule FailureRecorded do
    defstruct [:code, :user_message, :repair_action, :at]
  end

  defmodule Reverted do
    defstruct [:at]
  end

  defmodule RunDiscarded do
    @moduledoc """
    User chose not to act on a `:needs_user` run, or the TTL sweep auto-
    discarded a stale one. The event is permanent (immutable audit); the
    photo bytes attached to the run get deleted out-of-band.
    """
    defstruct [:reason, :at]
  end

  @type t ::
          %Opened{}
          | %PhaseEntered{}
          | %ToolStepRecorded{}
          | %ArtifactAdded{}
          | %ModelUsageObserved{}
          | %QuestionRaised{}
          | %QuestionAnswered{}
          | %Committed{}
          | %FailureRecorded{}
          | %Reverted{}
          | %RunDiscarded{}
end
