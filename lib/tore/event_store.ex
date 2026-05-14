defmodule Tore.EventStore do
  import Ecto.Query
  alias Tore.Repo

  defmodule Event do
    use Ecto.Schema

    schema "events" do
      field :stream_id, :string
      field :stream_type, :string
      field :event_type, :string
      field :data, :string
      field :metadata, :string
      field :inserted_at, :naive_datetime
    end
  end

  @spec load(String.t(), module()) :: {:ok, term()}
  def load(stream_id, decider) do
    events_module = events_module_for(decider)

    state =
      from(e in Event, where: e.stream_id == ^stream_id, order_by: [asc: e.id])
      |> Repo.all()
      |> Enum.reduce(decider.initial(), fn raw, acc ->
        event = deserialize(events_module, raw.event_type, raw.data)
        decider.evolve(acc, event)
      end)

    {:ok, state}
  end

  @spec append(String.t(), [struct()]) :: :ok | {:error, term()}
  def append(stream_id, events) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(events, fn event ->
        %{
          stream_id: stream_id,
          stream_type: stream_type_for(event),
          event_type: event.__struct__ |> Module.split() |> List.last(),
          data: Jason.encode!(Map.from_struct(event)),
          metadata: nil,
          inserted_at: now
        }
      end)

    Repo.insert_all(Event, rows)
    :ok
  rescue
    e -> {:error, e}
  end

  defp events_module_for(decider) do
    decider |> Module.split() |> List.replace_at(-1, "Events") |> Module.concat()
  end

  defp stream_type_for(event) do
    event.__struct__ |> Module.split() |> Enum.at(-3) |> String.downcase()
  end

  defp deserialize(events_module, event_type, data) do
    module = Module.concat([events_module, event_type])
    attrs = Jason.decode!(data, keys: :atoms)
    struct!(module, attrs)
  end
end
