defmodule Tore.LLM.PlannerTools do
  @moduledoc """
  Tool catalog for the planner agent. Each tool's `run` function takes
  string-keyed args from the LLM and a `ctx` map (must include :plan_id
  and :week_start). Action tools call PlanningHandler; read tools (built
  in Task 6) call Recipes/Pantry/Deals. `ask_user` is a terminal signal —
  the agent runtime recognises it and stops the loop.
  """

  alias Tore.LLM.Tool
  alias Tore.Handlers.PlanningHandler

  @slot_key %{type: "string", description: "Slot identifier like \"mon_dinner\""}
  @rationale %{type: "string",
    description: "One short clause explaining why you are making this change."}

  @spec all() :: [Tool.t()]
  def all do
    [
      assign_recipe(),
      swap_recipe(),
      skip_meal(),
      mark_leftover(),
      set_servings(),
      remove_recipe(),
      ask_user(),
      # Read-tool stubs — implemented in Task 6.
      search_recipes(),
      pantry_snapshot(),
      active_deals()
    ]
  end

  # ---------- Action tools ----------

  defp assign_recipe do
    %Tool{
      name: "assign_recipe",
      description: "Place a recipe in a slot. Sets servings.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{
          slot_key: @slot_key,
          recipe_id: %{type: "integer"},
          servings: %{type: "integer", minimum: 1},
          rationale: @rationale
        },
        required: ["slot_key", "recipe_id", "servings", "rationale"]
      },
      run: fn args, ctx ->
        with {:ok, _} <-
               PlanningHandler.assign_recipe(
                 ctx.plan_id, args["slot_key"], args["recipe_id"], args["servings"]
               ) do
          {:ok, %{ok: true, label: recipe_title(args["recipe_id"])}}
        end
      end
    }
  end

  defp swap_recipe do
    %Tool{
      name: "swap_recipe",
      description: "Atomically swap whatever is in from_slot_key and to_slot_key. No data loss.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{
          from_slot_key: @slot_key,
          to_slot_key: @slot_key,
          rationale: @rationale
        },
        required: ["from_slot_key", "to_slot_key", "rationale"]
      },
      run: fn args, ctx ->
        with {:ok, _events} <-
               PlanningHandler.swap_slots(ctx.plan_id, args["from_slot_key"], args["to_slot_key"]),
             {:ok, state} <- PlanningHandler.load_plan(ctx.plan_id) do
          to_slot = Map.get(state.slots, args["to_slot_key"]) || %{}
          {:ok, %{ok: true, label: recipe_title(to_slot[:recipe_id]), recipe_id: to_slot[:recipe_id]}}
        end
      end
    }
  end

  defp skip_meal do
    %Tool{
      name: "skip_meal",
      description: "Mark a slot as skipped. Neutral; no warning, no cascade.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{slot_key: @slot_key, rationale: @rationale},
        required: ["slot_key", "rationale"]
      },
      run: fn args, ctx ->
        PlanningHandler.skip_meal(ctx.plan_id, args["slot_key"]) |> wrap_ok()
      end
    }
  end

  defp mark_leftover do
    %Tool{
      name: "mark_leftover",
      description: "Mark a slot as leftovers from a prior meal.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{slot_key: @slot_key, rationale: @rationale},
        required: ["slot_key", "rationale"]
      },
      run: fn args, ctx ->
        PlanningHandler.mark_leftover(ctx.plan_id, args["slot_key"]) |> wrap_ok()
      end
    }
  end

  defp set_servings do
    %Tool{
      name: "set_servings",
      description: "Change servings for a slot's recipe.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{slot_key: @slot_key, servings: %{type: "integer", minimum: 1}, rationale: @rationale},
        required: ["slot_key", "servings", "rationale"]
      },
      run: fn args, ctx ->
        PlanningHandler.set_servings(ctx.plan_id, args["slot_key"], args["servings"]) |> wrap_ok()
      end
    }
  end

  defp remove_recipe do
    %Tool{
      name: "remove_recipe",
      description: "Clear a slot.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{slot_key: @slot_key, rationale: @rationale},
        required: ["slot_key", "rationale"]
      },
      run: fn args, ctx ->
        PlanningHandler.remove_recipe(ctx.plan_id, args["slot_key"]) |> wrap_ok()
      end
    }
  end

  defp ask_user do
    %Tool{
      name: "ask_user",
      description:
        "Surface a clarifying question to the user instead of guessing. Terminal: the agent stops the loop and shows the question.",
      kind: :read,
      parameters: %{
        type: "object",
        properties: %{question: %{type: "string"}},
        required: ["question"]
      },
      run: fn args, _ctx -> {:ok, %{ask_user: args["question"]}} end
    }
  end

  # ---------- Read tools ----------

  defp search_recipes do
    %Tool{
      name: "search_recipes",
      description:
        "Search the recipe catalog. Combine query text and max cooking time, plus an optional limit. Use this before assigning a recipe so you have a real recipe_id.",
      kind: :read,
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Free-text search across titles and ingredients"},
          max_minutes: %{type: "integer", minimum: 1},
          limit: %{type: "integer", minimum: 1, maximum: 25}
        },
        required: []
      },
      run: fn args, _ctx ->
        limit = Map.get(args, "limit", 8)
        max_minutes = args["max_minutes"]

        base =
          case args["query"] do
            q when is_binary(q) and byte_size(q) > 0 ->
              results = Tore.Recipes.search(q)

              if is_integer(max_minutes) do
                Enum.filter(results, &recipe_under_minutes?(&1, max_minutes))
              else
                results
              end

            _ ->
              opts = if is_integer(max_minutes), do: [max_minutes: max_minutes], else: []
              Tore.Recipes.list(opts)
          end

        result =
          base
          |> Enum.take(limit)
          |> Enum.map(&summarise_recipe/1)

        {:ok, %{recipes: result}}
      end
    }
  end

  defp pantry_snapshot do
    %Tool{
      name: "pantry_snapshot",
      description:
        "Approximate pantry inventory. Treat results as inexact — items may be missing or stale. Use before suggesting recipes that depend on specific ingredients.",
      kind: :read,
      parameters: %{type: "object", properties: %{}, required: []},
      run: fn _args, _ctx ->
        items =
          Tore.Pantry.list_inventory()
          |> Enum.map(fn it ->
            %{
              id: it.id,
              name: it.name,
              quantity: it.quantity && Decimal.to_string(it.quantity),
              unit: it.unit,
              category: it.category
            }
          end)

        {:ok, %{items: items}}
      end
    }
  end

  defp active_deals do
    %Tool{
      name: "active_deals",
      description:
        "Currently active store deals across configured stores. Use before suggesting recipes that align with current promotions.",
      kind: :read,
      parameters: %{type: "object", properties: %{}, required: []},
      run: fn _args, _ctx ->
        deals =
          Tore.Deals.list_current()
          |> Enum.map(fn d ->
            %{
              id: d.id,
              product_name: d.product_name,
              brand: d.brand,
              store: d.store,
              chain: d.chain,
              price: d.price && Decimal.to_string(d.price),
              price_unit: d.price_unit
            }
          end)

        {:ok, %{deals: deals}}
      end
    }
  end

  defp recipe_under_minutes?(%{prep_time_minutes: _, cook_time_minutes: _} = recipe, max) do
    total_minutes(recipe) <= max
  end

  defp recipe_under_minutes?(_, _), do: false

  defp summarise_recipe(r) do
    %{
      id: r.id,
      title: r.title,
      base_servings: r.base_servings,
      total_minutes: total_minutes(r)
    }
  end

  defp total_minutes(%{prep_time_minutes: p, cook_time_minutes: c}) do
    (p || 0) + (c || 0)
  end

  defp total_minutes(_), do: 0

  defp recipe_title(nil), do: nil

  defp recipe_title(recipe_id) do
    Tore.Recipes.get!(recipe_id).title
  rescue
    Ecto.NoResultsError -> nil
  end

  defp wrap_ok({:ok, _}), do: {:ok, %{ok: true}}
  defp wrap_ok({:error, reason}), do: {:error, reason}
end
