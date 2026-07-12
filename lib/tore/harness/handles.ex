defmodule Tore.Harness.Handles do
  @moduledoc """
  Resolved references (SPEC.md §A.6.2). A handle carries the resolved id,
  a human label, the resolver that produced it, a confidence, and an opaque
  `ref` token. The LLM only ever sees and repeats `ref`s; the PlannerAgent
  runtime exchanges refs for handles via a per-run registry, so an invented
  or stale ref is rejected before any action tool runs.
  """

  defmodule ResolvedRecipe do
    @moduledoc "A handle resolved to a recipe id."

    @enforce_keys [:id, :label, :source, :confidence, :ref]
    defstruct [:id, :label, :source, :confidence, :ref]

    @type t :: %__MODULE__{
            id: term(),
            label: String.t(),
            source: atom(),
            confidence: float(),
            ref: String.t()
          }
  end

  defmodule ResolvedSlot do
    @moduledoc "A handle resolved to a plan slot key."

    @enforce_keys [:slot_key, :label, :source, :confidence, :ref]
    defstruct [:slot_key, :label, :source, :confidence, :ref]

    @type t :: %__MODULE__{
            slot_key: String.t(),
            label: String.t(),
            source: atom(),
            confidence: float(),
            ref: String.t()
          }
  end

  @type handle :: ResolvedRecipe.t() | ResolvedSlot.t()
  @type registry :: %{optional(String.t()) => handle()}

  @spec recipe(term(), String.t(), atom(), float()) :: ResolvedRecipe.t()
  def recipe(id, label, source, confidence) do
    %ResolvedRecipe{
      id: id,
      label: label,
      source: source,
      confidence: confidence,
      ref: token("rcp")
    }
  end

  @spec slot(String.t(), String.t()) :: ResolvedSlot.t()
  def slot(slot_key, label) do
    %ResolvedSlot{
      slot_key: slot_key,
      label: label,
      source: :direct_touch,
      confidence: 1.0,
      ref: token("slt")
    }
  end

  @spec register(registry(), handle()) :: registry()
  def register(registry, %{ref: ref} = handle), do: Map.put(registry, ref, handle)

  @spec fetch(registry(), String.t() | nil) :: {:ok, handle()} | :error
  def fetch(registry, ref) when is_binary(ref), do: Map.fetch(registry, ref)
  def fetch(_registry, _), do: :error

  defp token(prefix),
    do: prefix <> "_" <> Base.url_encode64(:crypto.strong_rand_bytes(4), padding: false)
end
