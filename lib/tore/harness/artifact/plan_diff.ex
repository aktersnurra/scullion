defmodule Tore.Harness.Artifact.PlanDiff do
  @behaviour Tore.Harness.Artifact

  @type event_entry :: %{
          slot_key: String.t(),
          event_type: String.t(),
          payload: map(),
          rationale: [String.t()]
        }

  @type rollup_change :: :added | :swapped | :skipped | :leftover | :removed | :servings

  @type rollup_entry :: %{
          slot_key: String.t(),
          change: rollup_change(),
          label: String.t() | nil,
          rationale: [String.t()]
        }

  @derive Jason.Encoder
  @enforce_keys [:plan_stream_id, :week_start, :events]
  defstruct [:plan_stream_id, :week_start, :events]

  @type t :: %__MODULE__{
          plan_stream_id: String.t(),
          week_start: Date.t(),
          events: [event_entry()]
        }

  @impl true
  def kind, do: "PlanDiff"

  @spec summarise(t()) :: [rollup_entry()]
  def summarise(%__MODULE__{events: events}) do
    events
    |> Enum.group_by(& &1.slot_key)
    |> Enum.map(fn {slot_key, slot_events} -> rollup_for(slot_key, slot_events) end)
  end

  @impl true
  def summary(%__MODULE__{} = diff) do
    rollup = summarise(diff)
    counts = Enum.frequencies_by(rollup, & &1.change)
    %{counts: counts, text_fallback: text_from_counts(counts)}
  end

  @impl true
  def is_rationale_complete(%__MODULE__{events: events}),
    do: Enum.all?(events, fn e -> e.rationale != [] end)

  @impl true
  def to_json(%__MODULE__{plan_stream_id: psid, week_start: ws, events: events}) do
    %{
      "plan_stream_id" => psid,
      "week_start" => Date.to_iso8601(ws),
      "events" => Enum.map(events, &event_to_json/1)
    }
  end

  @impl true
  def from_json(%{"plan_stream_id" => psid, "week_start" => ws, "events" => events}) do
    %__MODULE__{
      plan_stream_id: psid,
      week_start: Date.from_iso8601!(ws),
      events: Enum.map(events, &event_from_json/1)
    }
  end

  defp event_to_json(%{slot_key: sk, event_type: et, payload: p, rationale: r}),
    do: %{"slot_key" => sk, "event_type" => et, "payload" => p, "rationale" => r}

  defp event_from_json(%{"slot_key" => sk, "event_type" => et, "payload" => p, "rationale" => r}),
    do: %{slot_key: sk, event_type: et, payload: p, rationale: r}

  defp rollup_for(slot_key, slot_events) do
    types = Enum.map(slot_events, & &1.event_type)
    rationale = slot_events |> Enum.flat_map(& &1.rationale)
    label = slot_events |> Enum.reverse() |> Enum.find_value(fn e -> e.payload["label"] end)

    change =
      cond do
        "RecipeSwapped" in types -> :swapped
        "RecipeAssigned" in types -> :added
        "MealSkipped" in types -> :skipped
        "LeftoverMarked" in types -> :leftover
        "RecipeRemoved" in types -> :removed
        "ServingsChanged" in types -> :servings
        true -> :added
      end

    %{slot_key: slot_key, change: change, label: label, rationale: rationale}
  end

  defp text_from_counts(counts) do
    counts
    |> Enum.map(fn {change, n} -> "#{n} #{change}" end)
    |> Enum.join(", ")
  end
end
