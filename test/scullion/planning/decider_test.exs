defmodule Scullion.Planning.DeciderTest do
  use ExUnit.Case, async: true

  alias Scullion.Planning.{Decider, State}

  test "initial/0 returns empty plan state" do
    assert %State{week_start: nil, slots: %{}} = Decider.initial()
  end
end
