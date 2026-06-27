defmodule Tore.Harness.Run.State do
  defmodule Draft do
    @enforce_keys [:stream_id]
    defstruct [:stream_id]
  end

  defmodule Running do
    @enforce_keys [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :phase,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :phase,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
  end

  defmodule NeedsUser do
    @enforce_keys [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :question,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :question,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
  end

  defmodule Applied do
    @enforce_keys [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :committed_at,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :committed_at,
      :tool_trace,
      :artifacts,
      :model_usage,
      :undo_payload
    ]
  end

  defmodule Failed do
    @enforce_keys [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :failed_at,
      :failure_code,
      :failure_user_message,
      :failure_repair_action,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :failed_at,
      :failure_code,
      :failure_user_message,
      :failure_repair_action,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
  end

  defmodule Reverted do
    @enforce_keys [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :reverted_at,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :reverted_at,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
  end

  defmodule Discarded do
    @moduledoc """
    Terminal state after a user (or the TTL sweep) explicitly chose not to
    act on a `:needs_user` run. `discard_reason` is `:user_discarded` or
    `:ttl_expired`. Artifacts proposed before discard are retained in the
    event stream for audit; the run's photo bytes are deleted out-of-band.
    """
    @enforce_keys [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :discarded_at,
      :discard_reason,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
    defstruct [
      :stream_id,
      :household_id,
      :kind,
      :surface,
      :started_by,
      :user_id,
      :input,
      :opened_at,
      :discarded_at,
      :discard_reason,
      :tool_trace,
      :artifacts,
      :model_usage
    ]
  end

  @type t ::
          %Draft{}
          | %Running{}
          | %NeedsUser{}
          | %Applied{}
          | %Failed{}
          | %Reverted{}
          | %Discarded{}

  @spec empty(String.t()) :: Draft.t()
  def empty(stream_id), do: %Draft{stream_id: stream_id}
end
