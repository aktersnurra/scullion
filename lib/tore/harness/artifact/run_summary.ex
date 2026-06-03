defmodule Tore.Harness.Artifact.RunSummary do
  @behaviour Tore.Harness.Artifact
  alias Tore.Harness.Artifact

  @type outcome :: :applied | :needs_user | :failed

  @derive Jason.Encoder
  @enforce_keys [:counts, :outcome]
  defstruct [:counts, :outcome]

  @type t :: %__MODULE__{
          counts: %{atom() => non_neg_integer()},
          outcome: outcome()
        }

  @impl true
  def kind, do: "RunSummary"

  @spec from_artifacts([Artifact.t()], outcome()) :: t()
  def from_artifacts(domain_artifacts, outcome) do
    counts =
      domain_artifacts
      |> Enum.flat_map(fn art -> Map.to_list(Artifact.summary(art).counts) end)
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.update(acc, k, v, &(&1 + v)) end)

    %__MODULE__{counts: counts, outcome: outcome}
  end

  @impl true
  def summary(%__MODULE__{counts: c, outcome: o}),
    do: %{counts: c, text_fallback: text_for(c, o)}

  @impl true
  def is_rationale_complete(_), do: true

  @impl true
  def to_json(%__MODULE__{counts: c, outcome: o}) do
    %{
      "outcome" => Atom.to_string(o),
      "counts" => Map.new(c, fn {k, v} -> {Atom.to_string(k), v} end)
    }
  end

  @impl true
  def from_json(%{"outcome" => o, "counts" => c}) do
    %__MODULE__{
      outcome: String.to_existing_atom(o),
      counts: Map.new(c, fn {k, v} -> {String.to_existing_atom(k), v} end)
    }
  end

  defp text_for(counts, outcome) do
    body =
      counts
      |> Enum.map(fn {k, v} -> "#{v} #{k}" end)
      |> Enum.join(", ")

    case {body, outcome} do
      {"", :needs_user} -> "Question raised"
      {"", :failed} -> "Failed"
      {"", :applied} -> "Nothing to apply"
      {b, _} -> b
    end
  end
end
