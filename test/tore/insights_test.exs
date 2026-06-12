defmodule Tore.InsightsTest do
  use Tore.DataCase, async: false
  import Mox

  alias Tore.Insights
  alias Tore.Household

  setup :verify_on_exit!

  test "synthesise_weekly calls LLM and saves insights" do
    Tore.MockLLM
    |> expect(:synthesise_insights, fn summary ->
      assert is_binary(summary)

      {:ok,
       [
         %{
           kind: "skip_pattern",
           body: "Mondays are often skipped.",
           confidence: 0.75,
           evidence: []
         },
         %{
           kind: "time_preference",
           body: "Quick meals preferred mid-week.",
           confidence: 0.6,
           evidence: []
         }
       ]}
    end)

    assert {:ok, saved} = Insights.synthesise_weekly()
    assert length(saved) == 2
    assert hd(saved).status == "active"
    assert length(Household.list_active_insights()) == 2
  end

  test "synthesise_weekly supersedes old insights on re-run" do
    Tore.MockLLM
    |> expect(:synthesise_insights, 2, fn _summary ->
      {:ok, [%{kind: "skip_pattern", body: "Pattern detected.", confidence: 0.7, evidence: []}]}
    end)

    Insights.synthesise_weekly()
    Insights.synthesise_weekly()

    assert length(Household.list_active_insights()) == 1
  end

  test "synthesise_weekly returns error when LLM fails" do
    Tore.MockLLM
    |> expect(:synthesise_insights, fn _summary -> {:error, :rate_limited} end)

    assert {:error, :rate_limited} = Insights.synthesise_weekly()
    assert Household.list_active_insights() == []
  end
end
