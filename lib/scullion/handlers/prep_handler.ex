defmodule Scullion.Handlers.PrepHandler do
  alias Scullion.{Handlers.PlanningHandler, Prep, Recipes, SpendGuard}

  @llm Application.compile_env(:scullion, :llm_client)

  def generate_guide(plan_id, week_start) do
    with :ok <- SpendGuard.allow?(:generate_prep_guide),
         {:ok, plan_state} <- PlanningHandler.load_plan(plan_id) do
      plan_for_prompt = build_plan_for_prompt(plan_state, week_start)

      with {:ok, guide_data, usage} <- @llm.generate_prep_guide(plan_for_prompt),
           :ok <- SpendGuard.log_usage(:generate_prep_guide, usage) do
        attrs = Map.put(guide_data, "week_start", week_start)
        Prep.save_guide(attrs)
      end
    end
  end

  defp build_plan_for_prompt(plan_state, week_start) do
    days =
      Enum.map(plan_state.slots, fn {slot_key, slot} ->
        recipe = if slot.recipe_id, do: Recipes.get!(slot.recipe_id), else: nil
        %{slot_key: slot_key, recipe_title: recipe && recipe.title, servings: slot.servings}
      end)

    %{week_start: week_start, days: days}
  end
end
