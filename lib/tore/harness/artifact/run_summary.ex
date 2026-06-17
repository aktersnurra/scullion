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
      outcome: outcome_atom(o),
      counts: Map.new(c, fn {k, v} -> {count_key_atom(k), v} end)
    }
  end

  # Explicit closed-enum maps (not String.to_existing_atom) so artifact
  # rehydration during the Projector's boot-time replay can't depend on atom
  # interning order. See Tore.Harness.Run rehydrate/1 for the same rationale.
  defp outcome_atom("applied"), do: :applied
  defp outcome_atom("needs_user"), do: :needs_user
  defp outcome_atom("failed"), do: :failed

  defp count_key_atom("added"), do: :added
  defp count_key_atom("swapped"), do: :swapped
  defp count_key_atom("skipped"), do: :skipped
  defp count_key_atom("leftover"), do: :leftover
  defp count_key_atom("removed"), do: :removed
  defp count_key_atom("servings"), do: :servings
  defp count_key_atom("superseded"), do: :superseded
  defp count_key_atom("unchanged"), do: :unchanged

  defp text_for(counts, outcome) do
    body =
      counts
      |> Enum.map(fn {k, v} -> "#{v} #{change_label(k)}" end)
      |> Enum.join(", ")

    case {body, outcome} do
      {"", :needs_user} -> "Question raised"
      {"", :failed} -> "Failed"
      {"", :applied} -> "Nothing to apply"
      {b, _} -> b
    end
  end

  defp change_label(:added), do: "added"
  defp change_label(:swapped), do: "swapped"
  defp change_label(:skipped), do: "skipped"
  defp change_label(:leftover), do: "leftovers"
  defp change_label(:removed), do: "removed"
  defp change_label(:servings), do: "servings adjusted"
  defp change_label(:superseded), do: "superseded"
  defp change_label(:unchanged), do: "unchanged"
  defp change_label(other), do: to_string(other)
end
