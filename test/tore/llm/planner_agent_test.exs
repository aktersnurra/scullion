defmodule Tore.LLM.PlannerAgentTest do
  use Tore.DataCase, async: false
  import Mox
  setup :verify_on_exit!

  alias Tore.LLM.PlannerAgent

  @system_prompt "system: be brief"
  @ctx %{plan_id: "plan-1", week_start: ~D[2026-06-01], household_id: 1}

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

  test "run/4 does not write to ai_operations" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok, {:message, "ok"},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    {:ok, _} = PlannerAgent.run(@system_prompt, "x", @ctx, [])

    # No rows should have been inserted — the orchestrator owns persistence.
    assert Tore.AiOperations.list_for_run("anything") == []
  end

  test "run/4 returns {:question, q} when ask_user is invoked" do
    expect(Tore.MockLLM, :chat_with_tools, fn _, _, _, _ ->
      {:ok,
       {:tool_calls,
        [%{id: "c1", name: "ask_user", args: %{"question" => "which?"}}]},
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
        {:ok,
         {:tool_calls,
          [%{id: "c1", name: "search_recipes", args: %{"query" => "x"}}]},
         %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
      end
    end)

    assert {:ok, outcome} = PlannerAgent.run(@system_prompt, "loop", @ctx, max_round_trips: 2)
    assert match?({:capped, _}, outcome.result) or match?({:message, _}, outcome.result)
  end
end
