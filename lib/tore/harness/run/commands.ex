defmodule Tore.Harness.Run.Commands do
  defmodule Open do
    defstruct [:household_id, :kind, :surface, :started_by, :user_id, :input]
  end

  defmodule EnterPhase do
    defstruct [:phase]
  end

  defmodule RecordToolStep do
    defstruct [:step_index, :step_kind, :payload, :ai_operation_id]
  end

  defmodule AddArtifact do
    defstruct [:artifact]
  end

  defmodule ObserveModelUsage do
    defstruct [:prompt_tokens, :completion_tokens, :cost_usd]
  end

  defmodule RaiseQuestion do
    defstruct [:question]
  end

  defmodule AnswerQuestion do
    defstruct [:answer]
  end

  defmodule Commit do
    defstruct [:undo_payload]
  end

  defmodule RecordFailure do
    defstruct [:code, :user_message, :repair_action]
  end

  defmodule Revert do
    defstruct []
  end

  defmodule Discard do
    @moduledoc """
    Terminate a run without applying its artifacts. `reason` is a closed-enum
    atom — `:user_discarded` for explicit user action, `:ttl_expired` for the
    weekly sweep.
    """
    defstruct [:reason]
  end

  @type t ::
          %Open{}
          | %EnterPhase{}
          | %RecordToolStep{}
          | %AddArtifact{}
          | %ObserveModelUsage{}
          | %RaiseQuestion{}
          | %AnswerQuestion{}
          | %Commit{}
          | %RecordFailure{}
          | %Revert{}
          | %Discard{}
end
