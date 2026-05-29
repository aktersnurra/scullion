defmodule Tore.Chat.WeekContextTest do
  use ExUnit.Case, async: true

  alias Tore.Chat.WeekContext

  test "returns fallback for nil state" do
    assert WeekContext.build(nil) == "No meals planned this week."
  end

  test "returns fallback for empty slots" do
    assert WeekContext.build(%{slots: %{}}) == "No meals planned this week."
  end

  test "describes a skipped slot" do
    state = %{week_start: ~D[2026-05-25], slots: %{"mon_dinner" => %{skipped: true, recipe_id: nil, leftover: false}}}
    result = WeekContext.build(state)
    assert result =~ "Mon: skipped"
  end

  test "describes assigned slot" do
    state = %{week_start: ~D[2026-05-25], slots: %{"tue_dinner" => %{recipe_id: 42, skipped: false, leftover: false}}}
    result = WeekContext.build(state)
    assert result =~ "Tue: recipe 42"
  end

  test "describes leftover slot" do
    state = %{week_start: ~D[2026-05-25], slots: %{"wed_dinner" => %{recipe_id: 7, skipped: false, leftover: true}}}
    result = WeekContext.build(state)
    assert result =~ "Wed: leftover (recipe 7)"
  end
end
