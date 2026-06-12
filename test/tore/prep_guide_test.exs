defmodule Tore.PrepGuideTest do
  use ExUnit.Case, async: false

  import Mox

  alias Tore.Prep

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
    :ok
  end

  defp plan_id, do: "plan:2026-04-27"
  defp week_start, do: ~D[2026-04-27]

  defp mock_usage, do: %{prompt_tokens: 500, completion_tokens: 100, cost_usd: 0.0005}

  test "generate_guide calls LLM and persists prep guide" do
    Tore.MockLLM
    |> expect(:generate_prep_guide, fn _plan, _locale ->
      {:ok,
       %{
         "timeline" => [
           %{"step" => 1, "task" => "Preheat oven", "duration_min" => 5, "component" => nil}
         ],
         "cascade_map" => %{"mon_dinner" => "Roast Chicken"},
         "storage_notes" => "Chicken: 3 days",
         "daily_assembly" => %{"mon_dinner" => "Plate and serve"},
         "prep_session" => %{
           "proteins" => ["chicken"],
           "bases" => [],
           "sauces" => [],
           "vegetables" => []
         }
       }, mock_usage()}
    end)

    assert {:ok, guide} = Prep.generate_guide(plan_id(), week_start())
    assert guide.week_start == week_start()
    assert length(guide.timeline) == 1
    assert guide.storage_notes == "Chicken: 3 days"
  end

  test "generate_guide returns error when LLM fails" do
    Tore.MockLLM |> expect(:generate_prep_guide, fn _, _ -> {:error, :timeout} end)
    assert {:error, :timeout} = Prep.generate_guide(plan_id(), week_start())
  end

  test "generate_guide returns budget_exceeded when over limit" do
    Tore.Costs.log_llm_usage(%{
      feature: "seed",
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: 20.0
    })

    assert {:error, :budget_exceeded} = Prep.generate_guide(plan_id(), week_start())
  end
end
