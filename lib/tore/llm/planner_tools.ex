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
          servings: %{type: "integer", minimum: 1}
        },
        required: ["slot_key", "recipe_id", "servings"]
      },
      run: fn args, ctx ->
        PlanningHandler.assign_recipe(
          ctx.plan_id,
          args["slot_key"],
          args["recipe_id"],
          args["servings"]
        )
        |> wrap_ok()
      end
    }
  end

  defp swap_recipe do
    %Tool{
      name: "swap_recipe",
      description: "Move whatever is in from_slot_key into to_slot_key. The source slot is cleared.",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{
          from_slot_key: @slot_key,
          to_slot_key: @slot_key
        },
        required: ["from_slot_key", "to_slot_key"]
      },
      run: fn args, ctx ->
        with {:ok, state} <- PlanningHandler.load_plan(ctx.plan_id),
             slot when not is_nil(slot) <- Map.get(state.slots, args["from_slot_key"]),
             rid when not is_nil(rid) <- Map.get(slot, :recipe_id),
             servings <- Map.get(slot, :servings) || 2,
             {:ok, _} <- PlanningHandler.assign_recipe(ctx.plan_id, args["to_slot_key"], rid, servings),
             {:ok, _} <- PlanningHandler.remove_recipe(ctx.plan_id, args["from_slot_key"]) do
          {:ok, %{ok: true}}
        else
          nil -> {:error, :nothing_to_swap}
          {:error, reason} -> {:error, reason}
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
        properties: %{slot_key: @slot_key},
        required: ["slot_key"]
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
        properties: %{slot_key: @slot_key},
        required: ["slot_key"]
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
        properties: %{slot_key: @slot_key, servings: %{type: "integer", minimum: 1}},
        required: ["slot_key", "servings"]
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
        properties: %{slot_key: @slot_key},
        required: ["slot_key"]
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
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{question: %{type: "string"}},
        required: ["question"]
      },
      run: fn args, _ctx -> {:ok, %{ask_user: args["question"]}} end
    }
  end

  # ---------- Read tool stubs (implemented in Task 6) ----------

  defp search_recipes,
    do: %Tool{
      name: "search_recipes",
      description: "stub — implemented in Task 6",
      kind: :read,
      parameters: %{type: "object", properties: %{}, required: []},
      run: fn _, _ -> {:error, :not_implemented} end
    }

  defp pantry_snapshot,
    do: %Tool{
      name: "pantry_snapshot",
      description: "stub — implemented in Task 6",
      kind: :read,
      parameters: %{type: "object", properties: %{}, required: []},
      run: fn _, _ -> {:error, :not_implemented} end
    }

  defp active_deals,
    do: %Tool{
      name: "active_deals",
      description: "stub — implemented in Task 6",
      kind: :read,
      parameters: %{type: "object", properties: %{}, required: []},
      run: fn _, _ -> {:error, :not_implemented} end
    }

  defp wrap_ok({:ok, _}), do: {:ok, %{ok: true}}
  defp wrap_ok({:error, reason}), do: {:error, reason}
end
