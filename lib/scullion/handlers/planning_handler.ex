defmodule Scullion.Handlers.PlanningHandler do
  alias Scullion.{Deals, EventStore, Planning.Decider, Planning.Commands, Recipes, SpendGuard}
  alias Phoenix.PubSub

  @pubsub Scullion.PubSub
  @topic "plan"
  @llm Application.compile_env(:scullion, :llm_client)

  def load_plan(plan_id) do
    EventStore.load(plan_id, Decider)
  end

  def generate_plan(plan_id, week_start, opts \\ []) do
    mode = Keyword.get(opts, :mode, :from_catalog)

    with :ok <- SpendGuard.allow?(:generate_plan),
         {:ok, state} <- EventStore.load(plan_id, Decider) do
      context = build_plan_context(state, week_start, mode)

      with {:ok, llm_result, usage} <- @llm.generate_plan(context),
           :ok <- SpendGuard.log_usage(:generate_plan, usage),
           {:ok, slots} <- parse_llm_slots(llm_result),
           {:ok, events} <- Decider.decide(%Commands.GeneratePlan{week_start: week_start, slots: slots}, state),
           :ok <- EventStore.append(plan_id, events) do
        PubSub.broadcast(@pubsub, @topic, {:events, events})
        {:ok, events}
      end
    end
  end

  def assign_recipe(plan_id, slot_key, recipe_id, servings) do
    run(plan_id, %Commands.AssignRecipe{slot_key: slot_key, recipe_id: recipe_id, servings: servings})
  end

  def remove_recipe(plan_id, slot_key) do
    run(plan_id, %Commands.RemoveRecipe{slot_key: slot_key})
  end

  def set_servings(plan_id, slot_key, servings) do
    run(plan_id, %Commands.SetServings{slot_key: slot_key, servings: servings})
  end

  def pin_slot(plan_id, slot_key, pin) do
    run(plan_id, %Commands.PinSlot{slot_key: slot_key, pin: pin})
  end

  def unpin_slot(plan_id, slot_key) do
    run(plan_id, %Commands.UnpinSlot{slot_key: slot_key})
  end

  def skip_meal(plan_id, slot_key) do
    run(plan_id, %Commands.SkipMeal{slot_key: slot_key})
  end

  def mark_leftover(plan_id, slot_key) do
    run(plan_id, %Commands.MarkLeftover{slot_key: slot_key})
  end

  defp run(plan_id, command) do
    with {:ok, state} <- EventStore.load(plan_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(plan_id, events) do
      PubSub.broadcast(@pubsub, @topic, {:events, events})
      {:ok, events}
    end
  end

  defp build_plan_context(state, week_start, mode) do
    recipes =
      Recipes.list(sort: :alphabetical)
      |> Enum.map(fn r ->
        %{
          id: r.id,
          title: r.title,
          key_ingredients: Enum.map(Enum.take(r.recipe_ingredients, 3), & &1.ingredient.name),
          total_time_minutes: (r.prep_time_minutes || 0) + (r.cook_time_minutes || 0),
          tags: Enum.map(r.tags, & &1.name)
        }
      end)

    slot_keys =
      state.slots
      |> Map.keys()
      |> Kernel.++(default_slot_keys())
      |> Enum.uniq()

    %{
      recipes: recipes,
      slot_keys: slot_keys,
      pins: state.pins,
      pantry: [],
      deals: Enum.map(Deals.list_current(), fn d ->
        "#{d.product_name}#{if d.price, do: " #{d.price}kr", else: ""}"
      end),
      recent_recipes: [],
      week_start: week_start,
      mode: mode
    }
  end

  defp parse_llm_slots(%{"days" => days}) when is_list(days) do
    slots =
      days
      |> Enum.filter(fn d -> is_binary(d["slot_key"]) && is_integer(d["recipe_id"]) end)
      |> Map.new(fn d ->
        {d["slot_key"], %{recipe_id: d["recipe_id"], servings: d["servings"] || 2}}
      end)

    {:ok, slots}
  end

  defp parse_llm_slots(_), do: {:ok, %{}}

  defp default_slot_keys do
    for day <- ~w[mon tue wed thu fri sat sun], meal <- ~w[dinner], do: "#{day}_#{meal}"
  end
end
