defmodule Tore.Harness.Run do
  import Ecto.Query
  alias Tore.Harness.Run.{Decider, State}
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

    EventStore.append(stream_id, events, opts)
  end

  defp deserialize(event_type, data) do
    module = Module.concat([Tore.Harness.Run.Events, event_type])
    attrs = Jason.decode!(data, keys: :atoms)
    struct!(module, attrs)
  end
end
