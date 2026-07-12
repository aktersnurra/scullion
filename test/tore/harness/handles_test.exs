defmodule Tore.Harness.HandlesTest do
  use ExUnit.Case, async: true

  alias Tore.Harness.Handles
  alias Tore.Harness.Handles.{ResolvedRecipe, ResolvedSlot}

  test "recipe/4 mints a handle with a rcp_ ref and the given confidence" do
    h = Handles.recipe(42, "Salmon pasta", :search_recipes, 0.91)
    assert %ResolvedRecipe{id: 42, label: "Salmon pasta", source: :search_recipes} = h
    assert h.confidence == 0.91
    assert String.starts_with?(h.ref, "rcp_")
    refute Handles.recipe(42, "Salmon pasta", :search_recipes, 0.91).ref == h.ref
  end

  test "slot/2 mints a direct-touch handle with confidence 1.0" do
    h = Handles.slot("tue_dinner", "Tuesday dinner")
    assert %ResolvedSlot{slot_key: "tue_dinner", source: :direct_touch, confidence: 1.0} = h
    assert String.starts_with?(h.ref, "slt_")
  end

  test "register/2 and fetch/2 round-trip; unknown ref errors" do
    h = Handles.recipe(1, "A", :resolve_recipe, 0.8)
    reg = Handles.register(%{}, h)
    assert {:ok, ^h} = Handles.fetch(reg, h.ref)
    assert :error = Handles.fetch(reg, "rcp_nope")
    assert :error = Handles.fetch(reg, nil)
  end
end
