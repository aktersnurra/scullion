defmodule Tore.Harness.Capsules.WeekPlanCapsule do
  @behaviour Tore.Harness.Capsule

  alias Tore.Handlers.PlanningHandler

  @day_names ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  defstruct [:week_start, :slots]

  @type slot :: %{day: String.t(), date: Date.t(), status: :empty | :assigned | :skipped}
  @type t :: %__MODULE__{week_start: Date.t() | nil, slots: [slot()] | nil}

  @impl true
  def build(ctx) do
    case PlanningHandler.load_plan(ctx.plan_stream_id) do
      {:ok, state} ->
        %__MODULE__{week_start: ctx.week_start, slots: build_slots(state, ctx.week_start)}

      _ ->
        %__MODULE__{week_start: ctx.week_start, slots: nil}
    end
  rescue
    _ -> %__MODULE__{week_start: ctx.week_start, slots: nil}
  end

  @impl true
  def to_prompt(%__MODULE__{slots: nil}), do: nil

  def to_prompt(%__MODULE__{slots: slots}) do
    lines =
      Enum.map_join(slots, "\n", fn s ->
        "  #{s.day} #{Date.to_iso8601(s.date)}: #{s.status}"
      end)

    "This week's dinner plan:\n#{lines}"
  end

  defp build_slots(state, week_start) do
    Enum.with_index(@day_names, fn day_name, i ->
      date = Date.add(week_start, i)
      slot_key = "#{String.downcase(String.slice(day_name, 0..2))}_dinner"
      %{day: day_name, date: date, status: slot_status(Map.get(state.slots, slot_key))}
    end)
  end

  defp slot_status(nil), do: :empty
  defp slot_status(%{recipe_id: nil}), do: :empty
  defp slot_status(%{skipped: true}), do: :skipped
  defp slot_status(_slot), do: :assigned
end
