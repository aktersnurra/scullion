defmodule Tore.Adapters.OpenRouterTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  test "generate_plan returns valid structure with real API" do
    constraints = %{
      recipes: [],
      slot_keys: ["mon_dinner"],
      pins: %{},
      pantry: [],
      deals: [],
      recent_recipes: [],
      week_start: ~D[2026-04-27],
      mode: :from_catalog
    }

    assert {:ok, result, usage} = Tore.Adapters.OpenRouter.generate_plan(constraints)
    assert Map.has_key?(result, "days")
    assert is_float(usage.cost_usd)
  end
end
