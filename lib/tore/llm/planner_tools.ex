defmodule Tore.LLM.PlannerTools do
  @moduledoc """
  Tool catalog for the planner agent. Each tool's `run` function takes
  string-keyed args, a `ctx` map (must include :plan_id and :week_start),
  and a `working_plan` State. Action tools are pure proposals: they call
  the Decider against the in-memory working_plan and return
  `{:ok, result, events, next_plan}` — nothing is persisted. Read tools
  and `ask_user` return `{:ok, result, [], working_plan}`.
  """

  alias Tore.LLM.Tool
  alias Tore.Planning
  alias Tore.Planning.{Decider, Commands}
  alias Tore.Harness.{Handles, Resolvers}

  @slot_key %{type: "string", description: "Slot identifier like \"mon_dinner\""}
  @rationale %{
    type: "string",
    description: "One short clause explaining why you are making this change."
  }

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
      search_recipes(),
      resolve_recipe(),
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
          recipe_ref: %{
            type: "string",
            description: "a ref returned by search_recipes or resolve_recipe"
          },
          servings: %{type: "integer", minimum: 1},
          rationale: @rationale
        },
        required: ["slot_key", "recipe_ref", "servings", "rationale"]
      },
      run: fn args, _ctx, plan ->
        cmd = %Commands.AssignRecipe{
          slot_key: args["slot_key"],
          recipe_id: args["recipe_id"],
          servings: args["servings"]
        }

        propose(cmd, plan, %{ok: true, label: recipe_title(args["recipe_id"])})
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
      run: fn args, _ctx, plan ->
        case Planning.swap_events(plan, args["from_slot_key"], args["to_slot_key"]) do
          {:ok, events, next} ->
            to_recipe_id = get_in(next.slots, [args["to_slot_key"], :recipe_id])

            {:ok, %{ok: true, label: recipe_title(to_recipe_id)}, events, next}

          {:error, reason} ->
            {:error, reason}
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
      run: fn args, _ctx, plan ->
        propose(%Commands.SkipMeal{slot_key: args["slot_key"]}, plan, %{ok: true})
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
      run: fn args, _ctx, plan ->
        propose(%Commands.MarkLeftover{slot_key: args["slot_key"]}, plan, %{ok: true})
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
        properties: %{
          slot_key: @slot_key,
          servings: %{type: "integer", minimum: 1},
          rationale: @rationale
        },
        required: ["slot_key", "servings", "rationale"]
      },
      run: fn args, _ctx, plan ->
        propose(
          %Commands.SetServings{slot_key: args["slot_key"], servings: args["servings"]},
          plan,
          %{ok: true}
        )
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
      run: fn args, _ctx, plan ->
        propose(%Commands.RemoveRecipe{slot_key: args["slot_key"]}, plan, %{ok: true})
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
      run: fn args, _ctx, plan -> {:ok, %{ask_user: args["question"]}, [], plan} end
    }
  end

  # ---------- Read tools ----------

  defp search_recipes do
    %Tool{
      name: "search_recipes",
      description:
        "Search the recipe catalog. Combine query text and max cooking time, plus an optional limit. Use this before assigning a recipe so you have a ref to pass to assign_recipe.",
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
      run: fn args, _ctx, plan ->
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

        handles =
          base
          |> Enum.take(limit)
          |> Enum.map(&Handles.recipe(&1.id, &1.title, :search_recipes, 1.0))

        result =
          base
          |> Enum.take(limit)
          |> Enum.zip(handles)
          |> Enum.map(fn {r, h} -> Map.put(summarise_recipe(r), :ref, h.ref) end)

        {:ok, %{recipes: result, __handles__: handles}, [], plan}
      end
    }
  end

  defp resolve_recipe do
    %Tool{
      name: "resolve_recipe",
      description:
        "Resolve a natural-language recipe reference to a ref. Use this (or search_recipes) before assign_recipe.",
      kind: :read,
      parameters: %{
        type: "object",
        properties: %{query: %{type: "string"}},
        required: ["query"]
      },
      run: fn args, _ctx, plan ->
        case Resolvers.resolve_recipe(args["query"]) do
          {:ok, h} ->
            {:ok,
             %{
               match: %{ref: h.ref, label: h.label, confidence: h.confidence},
               __handles__: [h]
             }, [], plan}

          {:ambiguous, hs} ->
            {:ok,
             %{
               ambiguous:
                 Enum.map(hs, &%{ref: &1.ref, label: &1.label, confidence: &1.confidence}),
               note: "multiple matches — ask_user or refine",
               __handles__: hs
             }, [], plan}

          :not_found ->
            {:ok, %{not_found: true}, [], plan}
        end
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
      run: fn _args, _ctx, plan ->
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

        {:ok, %{items: items}, [], plan}
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
      run: fn _args, _ctx, plan ->
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

        {:ok, %{deals: deals}, [], plan}
      end
    }
  end

  defp recipe_under_minutes?(%{prep_time_minutes: _, cook_time_minutes: _} = recipe, max) do
    total_minutes(recipe) <= max
  end

  defp recipe_under_minutes?(_, _), do: false

  defp summarise_recipe(r) do
    %{
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

  # Decide one command against the working plan; on success evolve it and return events.
  defp propose(cmd, plan, result) do
    case Decider.decide(cmd, plan) do
      {:ok, events} ->
        next = Enum.reduce(events, plan, fn ev, acc -> Decider.evolve(acc, ev) end)
        {:ok, result, events, next}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
