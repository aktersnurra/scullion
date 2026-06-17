defmodule Tore.Harness.Artifact.MemoryUpdate do
  @moduledoc """
  Output of `:kitchen_memory_synthesis_run`. Carries the household insights
  added, superseded, and unchanged, each with its evidence pointers (event
  ids in the planning stream).
  """

  @behaviour Tore.Harness.Artifact

  @type insight :: %{
          kind: String.t(),
          body: String.t(),
          confidence: float(),
          evidence: [integer()]
        }

  @derive Jason.Encoder
  @enforce_keys [:added, :superseded, :unchanged]
  defstruct [:added, :superseded, :unchanged]

  @type t :: %__MODULE__{
          added: [insight()],
          superseded: [insight()],
          unchanged: [insight()]
        }

  @impl true
  def kind, do: "MemoryUpdate"

  @impl true
  def summary(%__MODULE__{added: a, superseded: s, unchanged: u}) do
    counts = %{added: length(a), superseded: length(s), unchanged: length(u)}
    %{counts: counts, text_fallback: text_from_counts(counts)}
  end

  @impl true
  def is_rationale_complete(%__MODULE__{added: added}) do
    Enum.all?(added, fn ins ->
      is_binary(ins.body) and ins.body != "" and is_list(ins.evidence)
    end)
  end

  @impl true
  def to_json(%__MODULE__{added: a, superseded: s, unchanged: u}) do
    %{
      "added" => Enum.map(a, &insight_to_json/1),
      "superseded" => Enum.map(s, &insight_to_json/1),
      "unchanged" => Enum.map(u, &insight_to_json/1)
    }
  end

  @impl true
  def from_json(%{"added" => a, "superseded" => s, "unchanged" => u}) do
    %__MODULE__{
      added: Enum.map(a, &insight_from_json/1),
      superseded: Enum.map(s, &insight_from_json/1),
      unchanged: Enum.map(u, &insight_from_json/1)
    }
  end

  defp insight_to_json(%{kind: k, body: b, confidence: c, evidence: e}),
    do: %{"kind" => k, "body" => b, "confidence" => c, "evidence" => e}

  defp insight_from_json(%{"kind" => k, "body" => b, "confidence" => c, "evidence" => e}),
    do: %{kind: k, body: b, confidence: c, evidence: e}

  defp text_from_counts(%{added: 0, superseded: 0, unchanged: 0}), do: "No insights"

  defp text_from_counts(c) do
    [
      labeled(c.added, "added"),
      labeled(c.superseded, "superseded"),
      labeled(c.unchanged, "unchanged")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp labeled(0, _), do: nil
  defp labeled(n, label), do: "#{n} #{label}"
end
