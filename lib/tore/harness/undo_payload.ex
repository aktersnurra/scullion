defmodule Tore.Harness.UndoPayload do
  @moduledoc """
  How a committed Run is reversed. Stored on `Events.Committed` so a
  rehydrated `State.Applied` carries everything Phase 3's compensators need
  without having to re-read external aggregates.

  Sum type encoded as `{kind, data}`:

    * `:event_sourced` — `%{stream_id, stream_type, event_types}`. Phase 3's
      compensator appends compensating events to the named stream.
    * `:snapshot` — `%{schema, changes}`. Phase 3's compensator restores the
      before-state on each affected row.
    * `:composite` — `%{children: [UndoPayload]}`. Compensators run in
      reverse order.
    * `:irreversible` — `%{reason}`. The Undo button is disabled; the row
      shows the reason.

  `from_artifacts/1` derives the payload from a run's typed artifacts at
  commit time. Each artifact kind has a hard-coded reversal strategy; an
  artifact this module doesn't recognise is treated as irreversible (the
  conservative default — Phase 3 can extend the dispatcher).
  """

  alias Tore.Harness.Artifact.{CostEntry, MemoryUpdate, PantryBeliefUpdate, PlanDiff, RunSummary}

  @kinds [:event_sourced, :snapshot, :composite, :irreversible]

  @derive Jason.Encoder
  @enforce_keys [:kind, :data]
  defstruct [:kind, :data]

  @type t :: %__MODULE__{kind: atom(), data: map()}

  def kinds, do: @kinds

  @doc """
  Compose a list of already-built child payloads (e.g. from each child Run
  of a turn-Run) into a single payload. Mirrors `from_artifacts/1`'s
  composition rules but works on payloads, not artifacts — needed when the
  children live in separate Run streams.
  """
  @spec compose([t() | nil]) :: t()
  def compose(payloads) when is_list(payloads) do
    case Enum.reject(payloads, &is_nil/1) do
      [] ->
        irreversible("no child payloads")

      [single] ->
        single

      multiple ->
        if Enum.any?(multiple, &(&1.kind == :irreversible)) do
          irreversible("bundle contains an irreversible child")
        else
          %__MODULE__{kind: :composite, data: %{children: multiple}}
        end
    end
  end

  @spec from_artifacts([struct()]) :: t()
  def from_artifacts([]),
    do: irreversible("run produced no reversible artifacts")

  def from_artifacts(artifacts) when is_list(artifacts) do
    payloads = Enum.map(artifacts, &payload_for/1)

    case Enum.reject(payloads, &(&1.kind == :noop)) do
      [] ->
        irreversible("run produced no reversible artifacts")

      [single] ->
        single

      multiple ->
        if Enum.any?(multiple, &(&1.kind == :irreversible)) do
          irreversible("composite run contains an irreversible artifact")
        else
          %__MODULE__{kind: :composite, data: %{children: multiple}}
        end
    end
  end

  # ----- per-artifact strategy ------------------------------------------------

  defp payload_for(%PlanDiff{plan_stream_id: sid, events: events}) do
    %__MODULE__{
      kind: :event_sourced,
      data: %{
        stream_id: sid,
        stream_type: "planning",
        event_types: Enum.map(events, & &1.event_type)
      }
    }
  end

  defp payload_for(%PantryBeliefUpdate{items: items}) do
    %__MODULE__{
      kind: :snapshot,
      data: %{
        schema: "Tore.Pantry.PantryItem",
        changes: Enum.map(items, &snapshot_change/1)
      }
    }
  end

  defp payload_for(%CostEntry{}),
    do: irreversible("cost ledger entries are not reversible from the receipt")

  defp payload_for(%MemoryUpdate{}),
    do: irreversible("memory updates are not reversible from the receipt")

  defp payload_for(%RunSummary{}),
    do: %__MODULE__{kind: :noop, data: %{}}

  defp payload_for(_other),
    do: irreversible("unknown artifact kind")

  defp snapshot_change(item) do
    %{
      change: item.change,
      name: item.name,
      quantity: item[:quantity],
      unit: item[:unit],
      provenance: item.provenance
    }
  end

  defp irreversible(reason),
    do: %__MODULE__{kind: :irreversible, data: %{reason: reason}}

  # ----- JSON round-trip ------------------------------------------------------

  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{kind: :composite, data: %{children: children}}) do
    %{"kind" => "composite", "data" => %{"children" => Enum.map(children, &to_json/1)}}
  end

  def to_json(%__MODULE__{kind: :snapshot, data: data}) do
    changes = Enum.map(data.changes, &snapshot_to_json/1)
    %{"kind" => "snapshot", "data" => %{"schema" => data.schema, "changes" => changes}}
  end

  def to_json(%__MODULE__{kind: kind, data: data}) when kind in @kinds do
    %{"kind" => Atom.to_string(kind), "data" => map_keys_to_strings(data)}
  end

  @spec from_json(map()) :: t()
  def from_json(%{"kind" => "composite", "data" => %{"children" => children}}) do
    %__MODULE__{
      kind: :composite,
      data: %{children: Enum.map(children, &from_json/1)}
    }
  end

  def from_json(%{"kind" => "snapshot", "data" => %{"schema" => schema, "changes" => changes}}) do
    %__MODULE__{
      kind: :snapshot,
      data: %{schema: schema, changes: Enum.map(changes, &snapshot_from_json/1)}
    }
  end

  def from_json(%{"kind" => kind_str, "data" => data}) do
    kind = String.to_existing_atom(kind_str)
    true = kind in @kinds
    %__MODULE__{kind: kind, data: map_keys_to_atoms(data)}
  end

  defp snapshot_to_json(change) do
    %{
      "change" => Atom.to_string(change.change),
      "name" => Map.get(change, :name),
      "quantity" => decimal_to_string(Map.get(change, :quantity)),
      "unit" => Map.get(change, :unit),
      "provenance" => Map.get(change, :provenance)
    }
  end

  defp snapshot_from_json(m) do
    %{
      change: String.to_existing_atom(m["change"]),
      name: m["name"],
      quantity: m["quantity"],
      unit: m["unit"],
      provenance: m["provenance"]
    }
  end

  defp map_keys_to_strings(data) when is_map(data),
    do: for({k, v} <- data, into: %{}, do: {to_string(k), v})

  defp map_keys_to_atoms(data) when is_map(data),
    do: for({k, v} <- data, into: %{}, do: {String.to_existing_atom(k), v})

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(%Decimal{} = d), do: Decimal.to_string(d)
  defp decimal_to_string(other), do: other
end
