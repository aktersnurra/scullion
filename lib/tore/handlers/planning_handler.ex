defmodule Tore.Handlers.PlanningHandler do
  alias Tore.{Deals, EventStore, Planning.Decider, Planning.Commands, Recipes, SpendGuard}
  alias Phoenix.PubSub

  @pubsub Tore.PubSub
  @topic "plan"
  @llm Application.compile_env(:tore, :llm_client)

  def load_plan(plan_id) do
    EventStore.load(plan_id, Decider)
  end

  def generate_plan(plan_id, week_start, opts \\ []) do
    mode = Keyword.get(opts, :mode, :from_catalog)
    dietary_guidance = Keyword.get(opts, :dietary_guidance)

    with :ok <- SpendGuard.allow?(:generate_plan),
         {:ok, state} <- EventStore.load(plan_id, Decider) do
      context = build_plan_context(state, week_start, mode, dietary_guidance)

      with {:ok, llm_result, usage} <- @llm.generate_plan(context),
           :ok <- SpendGuard.log_usage(:generate_plan, usage),
           {:ok, slots} <- parse_llm_slots(llm_result),
           {:ok, events} <-
             Decider.decide(%Commands.GeneratePlan{week_start: week_start, slots: slots}, state),
           :ok <- EventStore.append(plan_id, events) do
        PubSub.broadcast(@pubsub, @topic, {:events, events})
        {:ok, events}
      end
    end
  end

  def assign_recipe(plan_id, slot_key, recipe_id, servings) do
    run(plan_id, %Commands.AssignRecipe{
      slot_key: slot_key,
      recipe_id: recipe_id,
      servings: servings
    })
  end

  @doc """
  Assigns a recipe to `slot_key` and propagates the same recipe (marked as
  leftover) to each of `leftover_days` (e.g. ["wed_dinner", "thu_dinner"]).
  All events are appended in one EventStore append + one PubSub broadcast,
  so the UI sees a single state change.
  """
  def assign_with_leftovers(plan_id, slot_key, recipe_id, servings, leftover_days)
      when is_list(leftover_days) do
    with {:ok, state} <- EventStore.load(plan_id, Decider) do
      {:ok, primary_events} =
        Decider.decide(
          %Commands.AssignRecipe{slot_key: slot_key, recipe_id: recipe_id, servings: servings},
          state
        )

      state_after_primary = Enum.reduce(primary_events, state, &Decider.evolve(&2, &1))
      leftover_servings = max(div(servings, 2), 1)

      {leftover_events, _final_state} =
        Enum.reduce(leftover_days, {[], state_after_primary}, fn day, {acc, st} ->
          with {:ok, assign_evts} <-
                 Decider.decide(
                   %Commands.AssignRecipe{
                     slot_key: day,
                     recipe_id: recipe_id,
                     servings: leftover_servings
                   },
                   st
                 ),
               st1 = Enum.reduce(assign_evts, st, &Decider.evolve(&2, &1)),
               {:ok, leftover_evts} <-
                 Decider.decide(%Commands.MarkLeftover{slot_key: day}, st1),
               st2 = Enum.reduce(leftover_evts, st1, &Decider.evolve(&2, &1)) do
            {acc ++ assign_evts ++ leftover_evts, st2}
          else
            _ -> {acc, st}
          end
        end)

      events = primary_events ++ leftover_events

      with :ok <- EventStore.append(plan_id, events) do
        PubSub.broadcast(@pubsub, @topic, {:events, events})
        {:ok, events}
      end
    end
  end

  @doc "Pure: cross-assign events for swapping two slots in a given plan state."
  @spec swap_events(Tore.Planning.State.t(), String.t(), String.t()) ::
          {:ok, [Tore.Planning.Events.t()], Tore.Planning.State.t()} | {:error, :nothing_to_swap}
  def swap_events(state, slot_a, slot_b) do
    a = present(Map.get(state.slots, slot_a))
    b = present(Map.get(state.slots, slot_b))

    case swap_commands(slot_a, a, slot_b, b) do
      [] ->
        {:error, :nothing_to_swap}

      commands ->
        {events, final} =
          Enum.reduce(commands, {[], state}, fn cmd, {acc, st} ->
            {:ok, evts} = Decider.decide(cmd, st)
            st2 = Enum.reduce(evts, st, &Decider.evolve(&2, &1))
            {acc ++ evts, st2}
          end)

        {:ok, events, final}
    end
  end

  @doc """
  Atomically swaps the recipes (and their servings) between two slots in one
  append. If one slot is empty, the occupied recipe moves to the empty slot and
  the source is cleared. If both are empty, returns {:error, :nothing_to_swap}.
  """
  def swap_slots(plan_id, slot_a, slot_b) do
    with {:ok, state} <- EventStore.load(plan_id, Decider) do
      case swap_events(state, slot_a, slot_b) do
        {:error, :nothing_to_swap} = err ->
          err

        {:ok, events, _final} ->
          with :ok <- EventStore.append(plan_id, events) do
            PubSub.broadcast(@pubsub, @topic, {:events, events})
            {:ok, events}
          end
      end
    end
  end

  # A slot counts as present only if it actually holds a recipe.
  defp present(%{recipe_id: rid} = slot) when not is_nil(rid), do: slot
  defp present(_), do: nil

  # Both slots' values are read into a/b BEFORE any command runs, so the
  # cross-assign cannot clobber. Servings travel with the recipe.
  defp swap_commands(_slot_a, nil, _slot_b, nil), do: []

  defp swap_commands(slot_a, a, slot_b, nil) do
    [
      %Commands.AssignRecipe{slot_key: slot_b, recipe_id: a.recipe_id, servings: a.servings},
      %Commands.RemoveRecipe{slot_key: slot_a}
    ]
  end

  defp swap_commands(slot_a, nil, slot_b, b) do
    [
      %Commands.AssignRecipe{slot_key: slot_a, recipe_id: b.recipe_id, servings: b.servings},
      %Commands.RemoveRecipe{slot_key: slot_b}
    ]
  end

  defp swap_commands(slot_a, a, slot_b, b) do
    [
      %Commands.AssignRecipe{slot_key: slot_a, recipe_id: b.recipe_id, servings: b.servings},
      %Commands.AssignRecipe{slot_key: slot_b, recipe_id: a.recipe_id, servings: a.servings}
    ]
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

  # ── Per-slot suggestions ──────────────────────────────────────────────────

  alias Tore.{Pantry, Recipes.Recipe}

  @recency_window_days 14

  @doc """
  Rank recipes for a single slot using rule-based scoring. Optionally merges
  one LLM-generated suggestion at the top when `:include_llm` is true.

  Returns `{:ok, [%{recipe, reasons, score}, ...]}`.
  """
  def suggest_recipes_for_slot(plan_id, slot_key, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    include_llm = Keyword.get(opts, :include_llm, false)
    dietary_guidance = Keyword.get(opts, :dietary_guidance)

    with {:ok, state} <- EventStore.load(plan_id, Decider) do
      recipes =
        Recipes.list(sort: :alphabetical)
        |> Enum.map(&Recipes.get!(&1.id))

      pantry_names = pantry_ingredient_names()
      deals_names = deal_product_names()
      previous_slot_recipe = previous_day_recipe(state, slot_key, recipes)
      recent_ids = recent_recipe_ids()

      ranked =
        recipes
        |> Enum.map(fn r ->
          {score, reasons} =
            score_recipe(r, %{
              pantry: pantry_names,
              deals: deals_names,
              previous_recipe: previous_slot_recipe,
              recent_ids: recent_ids
            })

          %{recipe: r, reasons: reasons, score: score}
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      if include_llm do
        case llm_extra_suggestion(
               state,
               slot_key,
               recipes,
               ranked,
               pantry_names,
               deals_names,
               recent_ids,
               dietary_guidance
             ) do
          {:ok, extra} ->
            {:ok, [extra | ranked] |> Enum.uniq_by(& &1.recipe.id) |> Enum.take(limit + 1)}

          {:error, _} ->
            {:ok, ranked}
        end
      else
        {:ok, ranked}
      end
    end
  end

  defp score_recipe(recipe, ctx) do
    ingredient_names =
      recipe.recipe_ingredients
      |> Enum.map(& &1.ingredient.name)
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    pantry_overlap =
      MapSet.intersection(ingredient_names, ctx.pantry) |> MapSet.size()

    deal_overlap =
      MapSet.intersection(ingredient_names, ctx.deals) |> MapSet.size()

    leftover_overlap =
      case ctx.previous_recipe do
        nil ->
          0

        prev ->
          prev_ingredients =
            prev.recipe_ingredients
            |> Enum.map(&String.downcase(&1.ingredient.name))
            |> MapSet.new()

          MapSet.intersection(ingredient_names, prev_ingredients) |> MapSet.size()
      end

    pantry_only? =
      MapSet.size(ingredient_names) > 0 and
        MapSet.subset?(ingredient_names, ctx.pantry)

    recently_cooked? = recipe.id in ctx.recent_ids

    base_score =
      pantry_overlap * 3 +
        deal_overlap * 4 +
        leftover_overlap * 5 +
        if(pantry_only?, do: 6, else: 0)

    score = if recently_cooked?, do: base_score - 20, else: base_score

    reasons =
      []
      |> add_reason(pantry_only?, "Pantry-only")
      |> add_reason(leftover_overlap > 0 and ctx.previous_recipe, fn ->
        "Reuses #{ctx.previous_recipe.title}"
      end)
      |> add_reason(pantry_overlap > 0 and not pantry_only?, fn ->
        sample = pantry_sample(ingredient_names, ctx.pantry)
        "Uses pantry #{sample}"
      end)
      |> add_reason(deal_overlap > 0, fn ->
        sample = pantry_sample(ingredient_names, ctx.deals)
        "Cheap this week (#{sample})"
      end)
      |> add_reason(
        (recipe.base_servings || 0) >= 4 and recipe.recipe_type == :meal,
        "Makes leftovers"
      )
      |> add_reason(recently_cooked?, "Recently cooked")
      |> Enum.reverse()

    {score, reasons}
  end

  defp add_reason(reasons, false, _), do: reasons
  defp add_reason(reasons, nil, _), do: reasons
  defp add_reason(reasons, _truthy, fun) when is_function(fun, 0), do: [fun.() | reasons]
  defp add_reason(reasons, _truthy, text) when is_binary(text), do: [text | reasons]

  defp pantry_sample(ingredient_set, source_set) do
    ingredient_set
    |> MapSet.intersection(source_set)
    |> Enum.take(2)
    |> Enum.join(", ")
  end

  defp pantry_ingredient_names do
    Pantry.list_inventory()
    |> Enum.map(&String.downcase(&1.name))
    |> MapSet.new()
  end

  defp deal_product_names do
    Deals.list_current()
    |> Enum.map(&String.downcase(&1.product_name))
    |> MapSet.new()
  end

  defp assigned_recipes_in_state(state, recipes) do
    by_id = Map.new(recipes, &{&1.id, &1})

    state.slots
    |> Enum.flat_map(fn {sk, slot} ->
      case Map.get(by_id, slot.recipe_id) do
        nil -> []
        r -> [{sk, r, slot.leftover}]
      end
    end)
  end

  defp previous_day_recipe(state, slot_key, recipes) do
    days = ~w[mon tue wed thu fri sat sun]
    [day, _meal] = String.split(slot_key, "_", parts: 2)
    idx = Enum.find_index(days, &(&1 == day))

    case idx && idx > 0 && Enum.at(days, idx - 1) do
      nil ->
        nil

      false ->
        nil

      prev_day ->
        case Map.get(state.slots, "#{prev_day}_dinner") do
          nil -> nil
          %{recipe_id: nil} -> nil
          %{recipe_id: id} -> Enum.find(recipes, &(&1.id == id))
        end
    end
  end

  defp recent_recipe_ids do
    cutoff = DateTime.add(DateTime.utc_now(), -@recency_window_days * 86_400, :second)

    import Ecto.Query

    Tore.Repo.all(
      from r in Recipe,
        where: not is_nil(r.last_used_at) and r.last_used_at >= ^cutoff,
        select: r.id
    )
    |> MapSet.new()
  end

  defp llm_extra_suggestion(
         state,
         slot_key,
         recipes,
         ranked,
         pantry,
         deals,
         recent_ids,
         dietary_guidance
       ) do
    excluded_ids = Enum.map(ranked, & &1.recipe.id)
    candidate_ids = Enum.map(recipes, & &1.id)

    candidate_summary =
      Enum.map(recipes, fn r ->
        %{
          id: r.id,
          title: r.title,
          key_ingredients: Enum.map(Enum.take(r.recipe_ingredients, 3), & &1.ingredient.name),
          total_time_minutes: (r.prep_time_minutes || 0) + (r.cook_time_minutes || 0),
          tags: Enum.map(r.tags, & &1.name)
        }
      end)

    assigned_context =
      assigned_recipes_in_state(state, recipes)
      |> Enum.map(fn {sk, r, leftover} -> %{slot_key: sk, title: r.title, leftover: leftover} end)

    [day, meal] = String.split(slot_key, "_", parts: 2)

    context = %{
      slot_key: slot_key,
      day_label: "#{String.capitalize(day)} #{meal}",
      candidates: candidate_summary,
      candidate_recipe_ids: candidate_ids,
      assigned_context: assigned_context,
      pantry: MapSet.to_list(pantry),
      deals: MapSet.to_list(deals),
      recent_recipe_ids: MapSet.to_list(recent_ids),
      excluded_recipe_ids: excluded_ids,
      dietary_guidance: dietary_guidance
    }

    with :ok <- SpendGuard.allow?(:suggest_recipe),
         {:ok, %{recipe_id: rid, reasoning: reasoning}, usage} <-
           @llm.suggest_slot_recipe(context),
         :ok <- SpendGuard.log_usage(:suggest_recipe, usage),
         recipe when not is_nil(recipe) <- Enum.find(recipes, &(&1.id == rid)) do
      {:ok, %{recipe: recipe, reasons: [reasoning], score: 999}}
    else
      nil -> {:error, :recipe_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_plan_context(state, week_start, mode, dietary_guidance) do
    recipes =
      Recipes.list(sort: :alphabetical)
      |> Tore.Repo.preload(recipe_ingredients: :ingredient)
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
      deals:
        Enum.map(Deals.list_current(), fn d ->
          "#{d.product_name}#{if d.price, do: " #{d.price}kr", else: ""}"
        end),
      recent_recipes: [],
      week_start: week_start,
      mode: mode,
      dietary_guidance: dietary_guidance,
      week_mode_fragment: Tore.WeekMode.mode_prompt_fragment(Tore.WeekMode.get_current_mode())
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
