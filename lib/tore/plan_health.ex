defmodule Tore.PlanHealth do
  @type status :: :ready | :flexible | :fragile | :unplanned
  @type result :: {status(), String.t()}

  @weekdays ~w(mon tue wed thu fri)

  @spec compute(map()) :: result()
  def compute(plan_state) do
    slots = plan_state.slots || %{}
    week_keys = Enum.map(@weekdays, &"#{&1}_dinner")

    assigned = Enum.filter(week_keys, fn k ->
      slot = Map.get(slots, k)
      slot && slot.recipe_id && !slot.skipped
    end)

    skipped = Enum.filter(week_keys, fn k ->
      slot = Map.get(slots, k)
      slot && slot.skipped
    end)

    unplanned_count = length(week_keys) - length(assigned) - length(skipped)

    cond do
      length(assigned) == 0 ->
        {:unplanned, "No plan for this week yet."}

      length(skipped) > 0 ->
        {:fragile, "#{length(skipped)} slot(s) skipped — plan may need repair."}

      unplanned_count > 0 ->
        {:flexible, "#{unplanned_count} slot(s) unplanned."}

      true ->
        {:ready, "Plan looks good for the week."}
    end
  end
end
