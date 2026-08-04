defmodule Tore.Harness.AmbientScanRunTest do
  use Tore.DataCase, async: false
  import Mox

  setup :verify_on_exit!

  test "scan materializes verified notes with proposed runs and expires the previous batch" do
    {:ok, stale} =
      Tore.CounterNotes.create(%{
        surface: "home",
        kind: "swap_suggestion",
        title: "stale",
        body: "b"
      })

    expect(Tore.MockLLM, :text, fn _system, context, _opts ->
      assert context =~ "Recently dismissed"

      {:ok,
       %{
         "notes" => [
           %{
             "surface" => "home",
             "kind" => "freezer_fallback",
             "title" => "Frozen bolognese tonight?",
             "body" => "Busy evening.",
             "confidence" => "medium",
             "scoped_slot" => "mon_dinner",
             "command" => "assign the frozen bolognese to monday",
             "item" => nil
           },
           %{
             "surface" => "groceries",
             "kind" => "usual_item_missing",
             "title" => "Oat milk?",
             "body" => "You always buy it.",
             "confidence" => "high",
             "scoped_slot" => nil,
             "command" => nil,
             "item" => %{"name" => "oat milk", "quantity" => nil, "unit" => nil}
           },
           %{
             "surface" => "home",
             "kind" => "prophecy",
             "title" => "bad",
             "body" => "b",
             "confidence" => "low",
             "scoped_slot" => nil,
             "command" => nil,
             "item" => nil
           }
         ]
       }, %{prompt_tokens: 10, completion_tokens: 10, cost_usd: Decimal.new(0)}}
    end)

    assert {:ok, _} = Tore.Harness.AmbientScan.scan()

    home = Tore.CounterNotes.list_for_surface("home")
    groceries = Tore.CounterNotes.list_for_surface("groceries")

    assert [%{kind: "freezer_fallback", proposed_run: %{"kind" => "planner_command"}}] = home

    assert [
             %{
               kind: "usual_item_missing",
               proposed_run: %{"kind" => "add_item", "name" => "oat milk"}
             }
           ] = groceries

    assert Tore.Repo.get!(Tore.CounterNotes.CounterNote, stale.id).status == "expired"
  end

  test "a malformed LLM payload yields an empty batch, not a crash" do
    expect(Tore.MockLLM, :text, fn _s, _u, _o ->
      {:ok, %{"unexpected" => true},
       %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
    end)

    assert {:ok, _} = Tore.Harness.AmbientScan.scan()
    assert Tore.CounterNotes.list_for_surface("home") == []
  end
end
