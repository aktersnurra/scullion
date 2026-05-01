defmodule Scullion.Groceries.AggregatorTest do
  use ExUnit.Case, async: true

  alias Scullion.Groceries.Aggregator

  test "aggregate/1 returns empty list for no recipes" do
    assert [] = Aggregator.aggregate([])
  end
end
