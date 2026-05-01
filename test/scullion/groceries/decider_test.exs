defmodule Scullion.Groceries.DeciderTest do
  use ExUnit.Case, async: true

  alias Scullion.Groceries.{Decider, State}

  test "initial/0 returns empty grocery state" do
    assert %State{week_start: nil, items: %{}} = Decider.initial()
  end
end
