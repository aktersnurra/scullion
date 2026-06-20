defmodule Tore.Harness.Projector do
  use GenServer
  import Ecto.Query

  alias Tore.Harness.Run
  alias Tore.Harness.Run.State
  alias Tore.EventStore.Event
  alias Tore.Repo
  alias Tore.Harness.ProjectorRegistry

  defstruct [:household_id, :table]

  @stream_type "run"

  # ---------- Client ----------

  def start_link(household_id) do
    GenServer.start_link(__MODULE__, household_id,
      name: {:via, Registry, {ProjectorRegistry, household_id}}
    )
  end

  @spec latest_on_surface(integer(), atom()) :: State.t() | nil
  def latest_on_surface(household_id, surface) do
    with [{pid, _}] <- Registry.lookup(ProjectorRegistry, household_id),
         {:ok, %{table: table}} <- GenServer.call(pid, :state) do
      case :ets.lookup(table, {:surface, surface}) do
        [{_, stream_id}] ->
          case :ets.lookup(table, {:stream, stream_id}) do
            [{_, state}] -> state
            [] -> nil
          end

        [] ->
          nil
      end
    else
      _ -> nil
    end
  end

  @spec lookup(integer(), String.t()) :: State.t() | nil
  def lookup(household_id, stream_id) do
    with [{pid, _}] <- Registry.lookup(ProjectorRegistry, household_id),
         {:ok, %{table: table}} <- GenServer.call(pid, :state) do
      case :ets.lookup(table, {:stream, stream_id}) do
        [{_, state}] -> state
        [] -> lazy_load(stream_id)
      end
    else
      _ -> nil
    end
  end

  @doc """
  All `:needs_user` runs for the household — the inbox queue. Newest first.
  """
  @spec list_pending(integer()) :: [State.NeedsUser.t()]
  def list_pending(household_id) do
    with [{pid, _}] <- Registry.lookup(ProjectorRegistry, household_id),
         {:ok, %{table: table}} <- GenServer.call(pid, :state) do
      :ets.match_object(table, {{:stream, :_}, :_})
      |> Enum.flat_map(fn
        {_, %State.NeedsUser{} = s} -> [s]
        _ -> []
      end)
      |> Enum.sort_by(& &1.opened_at, {:desc, DateTime})
    else
      _ -> []
    end
  end

  # ---------- Server ----------

  @impl true
  def init(household_id) do
    table = :ets.new(:projector, [:set, :protected, read_concurrency: true])
    Phoenix.PubSub.subscribe(Tore.PubSub, "harness:household:#{household_id}")
    state = %__MODULE__{household_id: household_id, table: table}
    {:ok, replay_open_runs(state)}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, {:ok, state}, state}

  @impl true
  def handle_info({:run_event, stream_id, _event}, %__MODULE__{} = state) do
    {:ok, new_state} = Run.load(stream_id)
    :ets.insert(state.table, {{:stream, stream_id}, new_state})

    if surface = surface_of(new_state) do
      :ets.insert(state.table, {{:surface, surface}, stream_id})
    end

    Phoenix.PubSub.broadcast(
      Tore.PubSub,
      "harness:household:#{state.household_id}",
      {:run_state_changed, stream_id, new_state}
    )

    {:noreply, state}
  end

  def handle_info({:run_state_changed, _sid, _state}, %__MODULE__{} = state),
    do: {:noreply, state}

  defp replay_open_runs(%__MODULE__{household_id: hh, table: table} = state) do
    open_stream_ids(hh)
    |> Enum.each(fn sid ->
      {:ok, run_state} = Run.load(sid)

      if open?(run_state) do
        :ets.insert(table, {{:stream, sid}, run_state})
        if surface = surface_of(run_state), do: :ets.insert(table, {{:surface, surface}, sid})
      end
    end)

    state
  end

  defp open_stream_ids(hh) do
    from(e in Event,
      where: e.stream_type == ^@stream_type,
      select: e.stream_id,
      distinct: true
    )
    |> Repo.all()
    |> Enum.filter(fn sid ->
      case Run.load(sid) do
        {:ok, %State.Running{household_id: ^hh}} -> true
        {:ok, %State.NeedsUser{household_id: ^hh}} -> true
        _ -> false
      end
    end)
  end

  defp open?(%State.Running{}), do: true
  defp open?(%State.NeedsUser{}), do: true
  defp open?(_), do: false

  defp surface_of(%State.Running{surface: s}), do: to_atom(s)
  defp surface_of(%State.NeedsUser{surface: s}), do: to_atom(s)
  defp surface_of(%State.Applied{surface: s}), do: to_atom(s)
  defp surface_of(%State.Failed{surface: s}), do: to_atom(s)
  defp surface_of(%State.Reverted{surface: s}), do: to_atom(s)
  defp surface_of(_), do: nil

  defp to_atom(s) when is_atom(s), do: s
  defp to_atom(s) when is_binary(s), do: String.to_existing_atom(s)

  defp lazy_load(stream_id) do
    case Run.load(stream_id) do
      {:ok, %State.Draft{}} -> nil
      {:ok, state} -> state
    end
  end
end
