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
    assert {:unplanned, 0} = PlanHealth.compute(%{slots: %{}})
  end

  test "returns :ready when all 5 weekday slots have recipes" do
    state = make_state(~w(mon tue wed thu fri))
    assert {:ready, 0} = PlanHealth.compute(state)
  end

  test "returns :flexible with the unplanned count when some weekday slots are unplanned" do
    state = make_state(~w(mon tue))
    assert {:flexible, 3} = PlanHealth.compute(state)
  end

  test "returns :fragile with the skipped count when a slot is skipped" do
    slots = %{
      "mon_dinner" => %{recipe_id: 1, skipped: false},
      "tue_dinner" => %{recipe_id: nil, skipped: true},
      "wed_dinner" => %{recipe_id: 2, skipped: false},
      "thu_dinner" => %{recipe_id: 3, skipped: false},
      "fri_dinner" => %{recipe_id: 4, skipped: false}
    }

    assert {:fragile, 1} = PlanHealth.compute(%{slots: slots})
  end
end
