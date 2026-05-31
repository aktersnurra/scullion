defmodule Tore.LLM.PlannerAgentTest do
  use Tore.DataCase, async: false
  import Mox
  setup :verify_on_exit!

  alias Tore.LLM.PlannerAgent

  @plan_id "plan:test-agent"

  setup do
    {:ok, _} = Tore.Handlers.PlanningHandler.load_plan(@plan_id)
    %{ctx: %{plan_id: @plan_id, week_start: ~D[2026-06-01]}}
  end

  test "single round-trip ending in a message", %{ctx: ctx} do
    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok, {:message, "Nothing to change."}, %{prompt_tokens: 5, completion_tokens: 2}}
    end)

    assert {:ok, %{final_message: "Nothing to change.", actions: [], correlation_id: cid}} =
             PlannerAgent.run("look at next week", ctx)

    assert is_binary(cid)
    rows = Tore.AiOperations.list_by_correlation(cid)
    assert length(rows) >= 1
  end

  test "executes a single action and ends after a follow-up message", %{ctx: ctx} do
    {:ok, recipe} = Tore.Recipes.create(%{title: "T", base_servings: 2, instructions: "x"})
    {:ok, _} = Tore.Handlers.PlanningHandler.assign_recipe(@plan_id, "mon_dinner", recipe.id, 2)

    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok,
       {:tool_calls,
        [%{id: "c1", name: "skip_meal", args: %{"slot_key" => "mon_dinner"}}]},
       %{prompt_tokens: 8, completion_tokens: 4}}
    end)

    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok, {:message, "Skipped Monday."}, %{prompt_tokens: 12, completion_tokens: 3}}
    end)

    assert {:ok, %{final_message: "Skipped Monday.", actions: actions}} =
             PlannerAgent.run("skip mon dinner", ctx)

    assert [%{name: "skip_meal", ok: true}] = actions

    {:ok, state} = Tore.Handlers.PlanningHandler.load_plan(@plan_id)
    assert state.slots["mon_dinner"].skipped == true
  end

  test "ask_user terminates the loop with a question", %{ctx: ctx} do
    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok,
       {:tool_calls, [%{id: "c1", name: "ask_user", args: %{"question" => "Which salmon?"}}]},
       %{}}
    end)

    assert {:ok, %{question: "Which salmon?", actions: []}} =
             PlannerAgent.run("move the salmon", ctx)
  end

  test "round-trip cap forces a final summary", %{ctx: ctx} do
    {:ok, recipe} = Tore.Recipes.create(%{title: "X", base_servings: 2, instructions: "x"})
    {:ok, _} = Tore.Handlers.PlanningHandler.assign_recipe(@plan_id, "wed_dinner", recipe.id, 2)

    stub(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, tools, _opts ->
      case tools do
        [] -> {:ok, {:message, "Stopped after cap."}, %{}}
        _ ->
          {:ok,
           {:tool_calls, [%{id: "loop", name: "skip_meal", args: %{"slot_key" => "wed_dinner"}}]},
           %{}}
      end
    end)

    assert {:ok, %{final_message: "Stopped after cap.", capped: true}} =
             PlannerAgent.run("loop", ctx, max_round_trips: 2)
  end

  test "tool error is fed back to the model", %{ctx: ctx} do
    # First turn: try to skip_meal on an empty slot. Decider returns {:error, :slot_empty}.
    # Second turn: the model gives up with a message.
    stub(Tore.MockLLM, :chat_with_tools, fn _sys, msgs, _tools, _opts ->
      tool_role_present? =
        Enum.any?(msgs, fn m ->
          Map.get(m, :role) == "tool" or Map.get(m, "role") == "tool"
        end)

      if tool_role_present? do
        {:ok, {:message, "Couldn't skip — slot was empty."}, %{}}
      else
        {:ok,
         {:tool_calls,
          [%{id: "c1", name: "skip_meal", args: %{"slot_key" => "sat_dinner"}}]},
         %{}}
      end
    end)

    assert {:ok, %{final_message: "Couldn't skip — slot was empty.", actions: [%{ok: false}]}} =
             PlannerAgent.run("skip sat", ctx)
  end
end
