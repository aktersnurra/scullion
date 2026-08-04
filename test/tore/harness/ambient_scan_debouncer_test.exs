defmodule Tore.Harness.AmbientScan.DebouncerTest do
  use ExUnit.Case, async: false

  alias Tore.Harness.AmbientScan.Debouncer

  test "coalesces bursts of mutations into one scan after the quiet period" do
    test_pid = self()

    {:ok, pid} =
      Debouncer.start_link(
        name: nil,
        quiet_ms: 30,
        scan_fun: fn -> send(test_pid, :scanned) end
      )

    send(pid, {:events, [:a]})
    send(pid, {:events, [:b]})
    send(pid, {:events, [:c]})

    refute_receive :scanned, 20
    assert_receive :scanned, 100
    refute_receive :scanned, 100
  end
end
