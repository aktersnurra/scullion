defmodule Tore.Harness.AmbientScan.Debouncer do
  @moduledoc """
  Re-triggers the ambient scan after plan/shop mutations settle
  (design §10.4). Coalesces event bursts into one scan per quiet period;
  SpendGuard's :ambient_scan cooldown is the cost backstop.
  """
  use GenServer

  @topics ~w(plan shop_list)

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    quiet_ms =
      Keyword.get(
        opts,
        :quiet_ms,
        Application.get_env(:tore, :ambient_scan_quiet_ms, :timer.minutes(5))
      )

    scan_fun = Keyword.get(opts, :scan_fun, fn -> Tore.Harness.AmbientScan.scan() end)

    if Keyword.get(opts, :subscribe?, false) do
      Enum.each(@topics, &Phoenix.PubSub.subscribe(Tore.PubSub, &1))
    end

    {:ok, %{quiet_ms: quiet_ms, scan_fun: scan_fun, timer: nil}}
  end

  @impl true
  def handle_info({:events, _}, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    {:noreply, %{state | timer: Process.send_after(self(), :scan, state.quiet_ms)}}
  end

  def handle_info(:scan, state) do
    Task.start(state.scan_fun)
    {:noreply, %{state | timer: nil}}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
