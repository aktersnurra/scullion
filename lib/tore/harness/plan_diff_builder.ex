defmodule Tore.Harness.PlanDiffBuilder do
  @moduledoc """
  Pure: reconstructs a `PlanDiff` from a PlannerAgent tool trace by joining
  tool-call args to their results and keeping only successful action calls.
  """

  alias Tore.Harness.Artifact.PlanDiff

  @action_tools ~w(assign_recipe swap_recipe skip_meal mark_leftover set_servings remove_recipe)

  @spec build([map()], map()) :: PlanDiff.t()
  def build(tool_trace, ctx) do
    calls = index_calls(tool_trace)

    events =
      tool_trace
      |> Enum.filter(&(&1.step_kind == :tool_result))
      |> Enum.flat_map(fn entry -> event_from_result(entry, calls) end)

    %PlanDiff{
      plan_stream_id: ctx.plan_stream_id,
      week_start: ctx.week_start,
      events: events
    }
  end

  defp index_calls(tool_trace) do
    tool_trace
    |> Enum.filter(&(&1.step_kind == :tool_calls))
    |> Enum.flat_map(fn entry ->
      entry.payload
      |> fetch(:calls)
      |> Jason.decode!()
    end)
    |> Map.new(fn call -> {call["id"], %{name: call["name"], args: call["args"]}} end)
  end

  defp event_from_result(entry, calls) do
    id = fetch(entry.payload, :tool_call_id)
    result = fetch(entry.payload, :result)

    with %{name: name, args: args} <- Map.get(calls, id),
         true <- name in @action_tools,
         true <- success?(result),
         entry when is_map(entry) <- event_for(name, args, result) do
      [entry]
    else
      _ -> []
    end
  end

  defp event_for("assign_recipe", args, result) do
    event(args, "slot_key", "RecipeAssigned", %{
      "recipe_id" => args["recipe_id"],
      "servings" => args["servings"],
      "label" => label_of(result)
    })
  end

  defp event_for("swap_recipe", args, result) do
    event(args, "to_slot_key", "RecipeSwapped", %{
      "from_slot_key" => args["from_slot_key"],
      "to_slot_key" => args["to_slot_key"],
      "recipe_id" => fetch(result, :recipe_id),
      "label" => label_of(result)
    })
  end

  defp event_for("skip_meal", args, _result),
    do: event(args, "slot_key", "MealSkipped", %{})

  defp event_for("mark_leftover", args, _result),
    do: event(args, "slot_key", "LeftoverMarked", %{})

  defp event_for("remove_recipe", args, _result),
    do: event(args, "slot_key", "RecipeRemoved", %{})

  defp event_for("set_servings", args, _result),
    do: event(args, "slot_key", "ServingsChanged", %{"servings" => args["servings"]})

  defp event(args, slot_arg, event_type, payload) do
    %{
      slot_key: args[slot_arg],
      event_type: event_type,
      payload: payload,
      rationale: rationale_of(args)
    }
  end

  defp success?(result) when is_map(result),
    do: not (Map.has_key?(result, :error) or Map.has_key?(result, "error"))

  defp success?(_), do: false

  defp rationale_of(args) do
    case args["rationale"] do
      r when is_binary(r) and r != "" -> [r]
      _ -> []
    end
  end

  defp label_of(result), do: fetch(result, :label)

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, to_string(key))

  defp fetch(_, _), do: nil
end
