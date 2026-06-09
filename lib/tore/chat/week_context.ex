defmodule Tore.Chat.WeekContext do
  @days ~w[mon tue wed thu fri sat sun]
  @day_labels %{
    "mon" => "Mon",
    "tue" => "Tue",
    "wed" => "Wed",
    "thu" => "Thu",
    "fri" => "Fri",
    "sat" => "Sat",
    "sun" => "Sun"
  }

  @spec build(map() | nil) :: String.t()
  def build(nil), do: "No meals planned this week."
  def build(%{slots: slots}) when map_size(slots) == 0, do: "No meals planned this week."

  def build(%{week_start: week_start, slots: slots} = _state) do
    week_desc =
      if week_start do
        formatted = Calendar.strftime(week_start, "%A %d %b")
        "Week of #{formatted}. "
      else
        ""
      end

    slot_summaries =
      @days
      |> Enum.map(fn day -> {day, Map.get(slots, "#{day}_dinner")} end)
      |> Enum.reject(fn {_day, slot} -> is_nil(slot) end)
      |> Enum.map(fn {day, slot} -> format_slot(@day_labels[day], slot) end)

    if slot_summaries == [] do
      "No meals planned this week."
    else
      "#{week_desc}#{Enum.join(slot_summaries, "; ")}."
    end
  end

  def build(_state), do: "No meals planned this week."

  defp format_slot(label, %{skipped: true}), do: "#{label}: skipped"

  defp format_slot(label, %{leftover: true, recipe_id: id}) when not is_nil(id),
    do: "#{label}: leftover (recipe #{id})"

  defp format_slot(label, %{recipe_id: id}) when not is_nil(id),
    do: "#{label}: recipe #{id}"

  defp format_slot(label, _), do: "#{label}: unplanned"
end
