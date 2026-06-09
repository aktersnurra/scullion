defmodule Tore.Adapters.SynthesiseInsightsTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "synthesise_insights returns parsed insight list" do
    Tore.MockLLM
    |> expect(:synthesise_insights, fn summary ->
      assert is_binary(summary)

      {:ok,
       [
         %{
           kind: "skip_pattern",
           body: "Family skips Mondays often.",
           confidence: 0.8,
           evidence: [1, 2]
         },
         %{
           kind: "time_preference",
           body: "Quick meals preferred mid-week.",
           confidence: 0.6,
           evidence: [3]
         }
       ]}
    end)

    {:ok, insights} = Tore.MockLLM.synthesise_insights("Week 1: skipped mon_dinner (id:1)...")
    assert length(insights) == 2
    assert hd(insights).kind == "skip_pattern"
  end

  test "synthesise_insights propagates errors" do
    Tore.MockLLM
    |> expect(:synthesise_insights, fn _summary -> {:error, :rate_limited} end)

    assert {:error, :rate_limited} = Tore.MockLLM.synthesise_insights("summary")
  end
end
