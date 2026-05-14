defmodule Tore.Accounts.RateLimiter do
  use GenServer

  @table :tore_rate_limits

  # Lockout durations in seconds, keyed by failure count at which they trigger
  @lockouts %{5 => 60, 6 => 120, 7 => 300}
  @max_lockout 1800

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @spec check(String.t()) :: :ok | {:error, :locked, non_neg_integer()}
  def check(ip) do
    case :ets.lookup(@table, ip) do
      [{^ip, _failures, locked_until}] when not is_nil(locked_until) ->
        now = System.system_time(:second)
        if locked_until > now, do: {:error, :locked, locked_until - now}, else: :ok

      _ ->
        :ok
    end
  end

  @spec record_failure(String.t()) :: :ok
  def record_failure(ip), do: GenServer.call(__MODULE__, {:record_failure, ip})

  @spec record_success(String.t()) :: :ok
  def record_success(ip), do: GenServer.call(__MODULE__, {:record_success, ip})

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:record_failure, ip}, _from, state) do
    failures =
      case :ets.lookup(@table, ip) do
        [{^ip, f, _}] -> f + 1
        [] -> 1
      end

    locked_until = compute_lock(failures)
    :ets.insert(@table, {ip, failures, locked_until})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:record_success, ip}, _from, state) do
    :ets.delete(@table, ip)
    {:reply, :ok, state}
  end

  defp compute_lock(failures) when failures < 5, do: nil

  defp compute_lock(failures) do
    secs = Map.get(@lockouts, failures, @max_lockout)
    System.system_time(:second) + secs
  end
end
