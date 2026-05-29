defmodule Tore.Chat.SystemPrompt do
  alias Tore.{Family, Pantry, WeekMode}

  @spec build() :: String.t()
  def build do
    today = Date.utc_today()
    week_mode = WeekMode.get_current_mode()

    [
      role_section(),
      date_section(today),
      dietary_section(),
      week_mode_section(week_mode),
      week_context_section(today),
      pantry_section()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp role_section do
    "You are Tore, a friendly and practical AI cooking and meal planning assistant.\nHelp the household plan meals, manage groceries, and make the most of what they have.\nRespond conversationally in the user's language. Be concise and warm."
  end

  defp date_section(today) do
    "Today is #{Calendar.strftime(today, "%A, %B %-d, %Y")}."
  end

  defp dietary_section do
    prefs = Family.get_preferences()
    guidance = Family.prefs_to_dietary_guidance(prefs)
    if guidance, do: "Household preferences: #{guidance}.", else: nil
  end

  defp week_mode_section("normal"), do: nil

  defp week_mode_section(mode) do
    fragment = WeekMode.mode_prompt_fragment(mode)
    if fragment, do: "Current week mode: #{fragment}", else: nil
  end

  defp week_context_section(today) do
    dow = Date.day_of_week(today)
    week_start = Date.add(today, -(dow - 1))
    plan_id = "plan:#{Date.to_iso8601(week_start)}"

    case Tore.EventStore.load(plan_id, Tore.Planning.Decider) do
      {:ok, state} -> format_plan_state(state, week_start)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp format_plan_state(state, week_start) do
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    lines =
      Enum.with_index(day_names, fn day_name, i ->
        date = Date.add(week_start, i)
        slot_key = "#{String.downcase(String.slice(day_name, 0..2))}_dinner"
        slot = Map.get(state.slots, slot_key)

        meal =
          cond do
            is_nil(slot) || is_nil(slot.recipe_id) -> "empty"
            slot.skipped -> "skipped"
            true -> "assigned"
          end

        "  #{day_name} #{Date.to_iso8601(date)}: #{meal}"
      end)

    "This week's dinner plan:\n#{Enum.join(lines, "\n")}"
  rescue
    _ -> nil
  end

  defp pantry_section do
    items = Pantry.list_inventory()

    if items == [] do
      nil
    else
      names = items |> Enum.map(& &1.name) |> Enum.take(20) |> Enum.join(", ")
      "Pantry has: #{names}#{if length(items) > 20, do: " and #{length(items) - 20} more", else: ""}."
    end
  rescue
    _ -> nil
  end
end
