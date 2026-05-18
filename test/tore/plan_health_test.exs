defmodule Tore.PlanHealthTest do
  use ExUnit.Case, async: true
  alias Tore.PlanHealth

  defp make_state(assigned_days) do
    slots =
      assigned_days
      |> Enum.map(fn day -> {"#{day}_dinner", %{recipe_id: 1, skipped: false}} end)
      |> Map.new()
    %{slots: slots}
  end

  test "returns :unplanned when no slots assigned" do
    {status, msg} = PlanHealth.compute(%{slots: %{}})
    assert status == :unplanned
    assert is_binary(msg)
  end

  test "returns :ready when all 5 weekday slots have recipes" do
    state = make_state(~w(mon tue wed thu fri))
    {status, _} = PlanHealth.compute(state)
    assert status == :ready
  end

  test "returns :flexible when some weekday slots are unplanned" do
    state = make_state(~w(mon tue))
    {status, msg} = PlanHealth.compute(state)
    assert status == :flexible
    assert String.contains?(msg, "3")
  end

  test "returns :fragile when a slot is skipped" do
    slots = %{
      "mon_dinner" => %{recipe_id: 1, skipped: false},
      "tue_dinner" => %{recipe_id: nil, skipped: true},
      "wed_dinner" => %{recipe_id: 2, skipped: false},
      "thu_dinner" => %{recipe_id: 3, skipped: false},
      "fri_dinner" => %{recipe_id: 4, skipped: false}
    }
    {status, _} = PlanHealth.compute(%{slots: slots})
    assert status == :fragile
  end
end
