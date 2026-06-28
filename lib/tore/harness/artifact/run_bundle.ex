defmodule Tore.Harness.Artifact.RunBundle do
  @moduledoc """
  A parent turn-Run's manifest of the child Runs it owns. Produced by
  `:capture_turn_run` so a single Capture turn can be represented as one
  receipt with one Undo, even when the turn produced multiple state
  changes.

  The bundle carries only the child stream ids; each child's own typed
  artifact is the source of truth for what changed and how to reverse it.
  `Tore.Harness.UndoPayload.from_artifacts/1` composes the bundle by
  loading each child's payload and wrapping them in a `:composite`.
  """

  @behaviour Tore.Harness.Artifact

  @derive Jason.Encoder
  @enforce_keys [:child_stream_ids]
  defstruct [:child_stream_ids]

  @type t :: %__MODULE__{child_stream_ids: [String.t()]}

  @impl true
  def kind, do: "RunBundle"

  @impl true
  def summary(%__MODULE__{child_stream_ids: ids}),
    do: %{counts: %{children: length(ids)}, text_fallback: "#{length(ids)} child runs"}

  @impl true
  def is_rationale_complete(_), do: true

  @impl true
  def to_json(%__MODULE__{child_stream_ids: ids}),
    do: %{"child_stream_ids" => ids}

  @impl true
  def from_json(%{"child_stream_ids" => ids}),
    do: %__MODULE__{child_stream_ids: ids}
end
