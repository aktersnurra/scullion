defmodule Tore.SpendGuardTest do
  use ExUnit.Case, async: false

  alias Tore.SpendGuard

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
  end

  test "allow? returns :ok when under budget" do
    assert :ok = SpendGuard.allow?(:generate_plan)
  end

  test "allow? returns budget_exceeded when over monthly limit" do
    Tore.Costs.log_llm_usage(%{
      feature: "seed",
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: 20.0
    })

    assert {:error, :budget_exceeded} = SpendGuard.allow?(:generate_plan)
  end

  test "allow? returns cooldown when same feature called within 60s" do
    Tore.Costs.log_llm_usage(%{
      feature: "generate_plan",
      prompt_tokens: 100,
      completion_tokens: 50,
      cost_usd: 0.001
    })

    assert {:error, :cooldown} = SpendGuard.allow?(:generate_plan)
  end

  test "allow? does not apply cooldown across different features" do
    Tore.Costs.log_llm_usage(%{
      feature: "generate_prep_guide",
      prompt_tokens: 100,
      completion_tokens: 50,
      cost_usd: 0.001
    })

    assert :ok = SpendGuard.allow?(:generate_plan)
  end

  test "log_usage inserts a usage record" do
    usage = %{prompt_tokens: 1000, completion_tokens: 200, cost_usd: 0.005}
    assert :ok = SpendGuard.log_usage(:generate_plan, usage)
    assert Tore.Costs.llm_spend_this_month() >= 0.005
  end
end
