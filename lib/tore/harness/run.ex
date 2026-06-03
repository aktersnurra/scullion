defmodule Tore.Harness.Run do
  import Ecto.Query
  alias Tore.Harness.Run.{Decider, Events, State}
  alias Tore.Harness.Artifact
  alias Tore.EventStore
  alias Tore.EventStore.Event
  alias Tore.Repo

  @stream_type "run"

  @spec next_stream_id() :: String.t()
  def next_stream_id,
    do: "run-" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))

  @spec load(String.t()) :: {:ok, State.t()}
  def load(stream_id) do
    state =
      from(e in Event,
        where: e.stream_id == ^stream_id and e.stream_type == ^@stream_type,
        order_by: [asc: e.id]
      )
      |> Repo.all()
      |> Enum.reduce(%State.Draft{stream_id: stream_id}, fn raw, acc ->
        event = deserialize(raw.event_type, raw.data)
        Decider.evolve(acc, event)
      end)

    {:ok, state}
  end

  defdelegate decide(command, state), to: Decider
  defdelegate evolve(state, event), to: Decider

  @spec append(String.t(), [struct()], map()) :: :ok | {:error, term()}
  def append(stream_id, events, metadata \\ %{}) do
    opts =
      case Map.get(metadata, :household_id) do
        nil -> []
        hh -> [broadcast: "harness:household:#{hh}", broadcast_tag: :run_event]
      end

    EventStore.append(stream_id, Enum.map(events, &prepare/1), opts)
  end

  defp prepare(%Events.ArtifactAdded{artifact: %_{} = artifact} = ev),
    do: %Events.ArtifactAdded{ev | artifact: Artifact.to_json(artifact)}

  defp prepare(event), do: event

  defp deserialize(event_type, data) do
    module = Module.concat([Tore.Harness.Run.Events, event_type])
    attrs = Jason.decode!(data, keys: :atoms)
    rehydrate(struct!(module, attrs))
  end

  defp rehydrate(%Events.ArtifactAdded{artifact: payload}) when is_map(payload) do
    %Events.ArtifactAdded{artifact: rehydrate_artifact(payload)}
  end

  defp rehydrate(event), do: event

  defp rehydrate_artifact(payload) do
    kind = Map.get(payload, :__kind__) || Map.get(payload, "__kind__")
    {:ok, module} = Artifact.Registry.lookup(kind)
    module.from_json(stringify_keys(payload))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(v), do: v
end
