defmodule Tore.Harness.Verifier.CounterNoteVerifierTest do
  use ExUnit.Case, async: true

  alias Tore.Harness.Verifier.CounterNoteVerifier, as: V

  @valid %{
    "surface" => "home",
    "kind" => "swap_suggestion",
    "title" => "Swap with Thursday?",
    "body" => "Tuesdays go quick.",
    "confidence" => "medium",
    "scoped_slot" => "tue_dinner",
    "command" => "swap tuesday's dinner with thursday's"
  }
  @slot_keys MapSet.new(
               ~w(mon_dinner tue_dinner wed_dinner thu_dinner fri_dinner sat_dinner sun_dinner)
             )

  test "a valid proposal passes" do
    assert :ok = V.verify(@valid, @slot_keys)
  end

  test "unknown kind, unknown surface, blank title fail" do
    assert {:fail, _, _} = V.verify(%{@valid | "kind" => "prophecy"}, @slot_keys)
    assert {:fail, _, _} = V.verify(%{@valid | "surface" => "tv"}, @slot_keys)
    assert {:fail, _, _} = V.verify(%{@valid | "title" => "  "}, @slot_keys)
  end

  test "a scoped_slot outside the week's slot domain fails" do
    assert {:fail, _, _} = V.verify(%{@valid | "scoped_slot" => "mon_breakfast"}, @slot_keys)
  end

  test "swap_suggestion without a scoped_slot fails" do
    assert {:fail, _, _} = V.verify(Map.put(@valid, "scoped_slot", nil), @slot_keys)
  end

  test "informational note (no command) passes; empty-string command fails" do
    ok = @valid |> Map.put("command", nil) |> Map.put("kind", "missing_ingredient")
    assert :ok = V.verify(ok, @slot_keys)
    assert {:fail, _, _} = V.verify(%{@valid | "command" => ""}, @slot_keys)
  end

  test "usual_item_missing with an item passes; without fails" do
    item = %{
      "surface" => "groceries",
      "kind" => "usual_item_missing",
      "title" => "Oat milk?",
      "body" => "You always buy it and it's not on the list.",
      "confidence" => "high",
      "item" => %{"name" => "oat milk", "quantity" => nil, "unit" => nil}
    }

    assert :ok = V.verify(item, @slot_keys)
    assert {:fail, _, _} = V.verify(Map.delete(item, "item"), @slot_keys)
  end
end
