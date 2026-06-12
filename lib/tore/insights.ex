defmodule Tore.Insights do
  import Ecto.Query
  alias Tore.Household

  @llm Application.compile_env(:tore, :llm_client)
  @high_weight_types ~w[MealSkipped RecipeRemoved]

  @spec synthesise_weekly() :: {:ok, [Household.HouseholdInsight.t()]} | {:error, term()}
  def synthesise_weekly do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-28 * 86_400, :second)
      |> DateTime.to_naive()

    events =
      from(e in Tore.EventStore.Event,
        where: e.stream_type == "planning" and e.inserted_at >= ^cutoff,
        order_by: [asc: e.id]
      )
      |> Tore.Repo.all()

    summary = format_events_summary(events)

    with {:ok, insights} <- @llm.synthesise_insights(summary) do
      Household.replace_insights(insights)
    end
  end

  defp format_events_summary([]), do: "No planning events in the last 28 days."

  defp format_events_summary(events) do
    lines =
      Enum.map(events, fn e ->
        weight = if e.event_type in @high_weight_types, do: "[HIGH] ", else: ""
        "#{weight}#{e.event_type} (id:#{e.id}) stream:#{e.stream_id} at:#{e.inserted_at}"
      end)

    total = length(events)
    high = Enum.count(events, &(&1.event_type in @high_weight_types))

    "Planning event summary — last 28 days (#{total} events, #{high} high-signal):\n\n#{Enum.join(lines, "\n")}"
  end
end
