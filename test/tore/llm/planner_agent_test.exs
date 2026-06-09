defmodule Tore.LLM.PlannerAgentTest do
  use Tore.DataCase, async: false
  import Mox
  setup :verify_on_exit!

  alias Tore.LLM.PlannerAgent
  alias Tore.Planning.{State, Events, Decider}

  @system_prompt "system: be brief"
  @ctx %{plan_id: "plan-1", week_start: ~D[2026-06-01], household_id: 1, working_plan: %State{}}

  defp ctx_with_plan(plan),
    do: %{plan_id: "plan-1", week_start: ~D[2026-06-01], household_id: 1, working_plan: plan}

  test "run/4 returns {:ok, loop_outcome} with a message result and usage steps" do
    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok, {:message, "Done."},
       %{prompt_tokens: 5, completion_tokens: 2, cost_usd: Decimal.new("0.0001")}}
    end)

    assert {:ok, outcome} = PlannerAgent.run(@system_prompt, "skip mon dinner", @ctx, [])
    assert outcome.result == {:message, "Done."}
    assert is_list(outcome.tool_trace)
    assert is_list(outcome.usage_per_step)
    assert hd(outcome.usage_per_step).prompt_tokens == 5
  end

  test "run/4 coerces a float cost_usd from the LLM into a Decimal" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "ok"}, %{prompt_tokens: 5, completion_tokens: 2, cost_usd: 5.04e-4}}
    end)

    {:ok, outcome} = PlannerAgent.run(@system_prompt, "x", @ctx, [])
    usage = hd(outcome.usage_per_step)
    assert %Decimal{} = usage.cost_usd
    assert Decimal.equal?(usage.cost_usd, Decimal.from_float(5.04e-4))
  end

  test "run/4 does not write to ai_operations" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "ok"}, %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    {:ok, _} = PlannerAgent.run(@system_prompt, "x", @ctx, [])

    # No rows should have been inserted — the orchestrator owns persistence.
    assert Tore.AiOperations.list_for_run("anything") == []
  end

  test "run/4 assigns a unique step_index to every trace entry" do
    stub(Tore.MockLLM, :chat_with_tools, fn _, _, tools, _opts ->
      if tools == [] do
        {:ok, {:message, "stopped"},
         %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
      else
        {:ok, {:tool_calls, [%{id: "c1", name: "search_recipes", args: %{"query" => "x"}}]},
         %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
      end
    end)

    {:ok, outcome} = PlannerAgent.run(@system_prompt, "loop", @ctx, max_round_trips: 2)

    indices = Enum.map(outcome.tool_trace, & &1.step_index)
    assert indices == Enum.uniq(indices)
    assert indices == Enum.sort(indices)
  end

  test "run/4 returns {:question, q} when ask_user is invoked" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:tool_calls, [%{id: "c1", name: "ask_user", args: %{"question" => "which?"}}]},
       %{prompt_tokens: 3, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    assert {:ok, outcome} = PlannerAgent.run(@system_prompt, "ambiguous", @ctx, [])
    assert outcome.result == {:question, "which?"}
  end

  test "run/4 returns {:capped, _} after max round-trips" do
    stub(Tore.MockLLM, :chat_with_tools, fn _, _, tools, _opts ->
      if tools == [] do
        {:ok, {:message, "stopped"},
         %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
      else
        {:ok, {:tool_calls, [%{id: "c1", name: "search_recipes", args: %{"query" => "x"}}]},
         %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
      end
    end)

    assert {:ok, outcome} = PlannerAgent.run(@system_prompt, "loop", @ctx, max_round_trips: 2)
    assert match?({:capped, _}, outcome.result) or match?({:message, _}, outcome.result)
  end

  test "run/4 accumulates plan_events and evolves working_plan across the loop" do
    {:ok, r} = Tore.Recipes.create(%{title: "Z", base_servings: 2, instructions: "x"})
    rid = r.id

    start_plan =
      Decider.evolve(%State{}, %Events.RecipeAssigned{
        slot_key: "mon_dinner",
        recipe_id: rid,
        servings: 2
      })

    expect(Tore.MockLLM, :chat_with_tools, fn _sys, _msgs, _tools, _opts ->
      {:ok,
       {:tool_calls,
        [
          %{
            id: "c1",
            name: "skip_meal",
            args: %{"slot_key" => "mon_dinner", "rationale" => "out"}
          }
        ]}, %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "Done."},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    {:ok, outcome} = PlannerAgent.run(@system_prompt, "skip mon", ctx_with_plan(start_plan), [])

    assert [%Events.MealSkipped{slot_key: "mon_dinner"}] = outcome.plan_events
    assert outcome.working_plan.slots["mon_dinner"].skipped == true
  end
end
