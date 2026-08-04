defmodule Tore.CounterNotesTest do
  use Tore.DataCase, async: true
  alias Tore.CounterNotes
  alias Tore.CounterNotes.CounterNote
  alias Tore.Repo

  test "list_for_surface/1 returns pending notes for the given surface only" do
    {:ok, _} =
      CounterNotes.create(%{
        surface: "home",
        kind: "deal_opportunity",
        title: "Chicken deal",
        body: "ICA has chicken thighs 20% off."
      })

    {:ok, _} =
      CounterNotes.create(%{
        surface: "pantry",
        kind: "pantry_assumption",
        title: "Rice",
        body: "Probably have rice."
      })

    home_notes = CounterNotes.list_for_surface("home")
    assert length(home_notes) == 1
    assert hd(home_notes).surface == "home"
  end

  test "ignore/1 removes note from surface listing" do
    {:ok, note} =
      CounterNotes.create(%{
        surface: "home",
        kind: "deal_opportunity",
        title: "Test",
        body: "Test."
      })

    {:ok, _} = CounterNotes.ignore(note.id)
    assert CounterNotes.list_for_surface("home") == []
  end

  test "accept/1 sets status to accepted" do
    {:ok, note} =
      CounterNotes.create(%{
        surface: "home",
        kind: "habit_pattern",
        title: "Thursday",
        body: "You often skip Thursday."
      })

    {:ok, updated} = CounterNotes.accept(note.id)
    assert updated.status == "accepted"
  end

  test "expire_stale/0 marks expired notes" do
    past = DateTime.add(DateTime.utc_now(), -3600, :second)

    {:ok, _} =
      CounterNotes.create(%{
        surface: "week",
        kind: "plan_repair",
        title: "Fragile",
        body: "Week looks fragile.",
        expires_at: past
      })

    {count, _} = CounterNotes.expire_stale()
    assert count == 1
    assert CounterNotes.list_for_surface("week") == []
  end

  test "create accepts a proposed_run map and the new scan kinds" do
    {:ok, note} =
      CounterNotes.create(%{
        surface: "home",
        kind: "swap_suggestion",
        title: "Swap with Thursday?",
        body: "Tuesdays go quick — Thursday's dish is faster.",
        proposed_run: %{
          "kind" => "planner_command",
          "command" => "swap tuesday's dinner with thursday's",
          "scoped_slot" => "tue_dinner"
        }
      })

    assert note.proposed_run["kind"] == "planner_command"
  end

  test "create rejects an unknown kind" do
    assert {:error, changeset} =
             CounterNotes.create(%{surface: "home", kind: "nonsense", title: "t", body: "b"})

    assert %{kind: _} = errors_on(changeset)
  end

  test "replace_scan_notes expires previous pending scan notes and inserts the new set" do
    {:ok, old} =
      CounterNotes.create(%{surface: "home", kind: "swap_suggestion", title: "old", body: "b"})

    {:ok, keeper} =
      CounterNotes.create(%{surface: "home", kind: "habit_pattern", title: "manual", body: "b"})

    {:ok, [new_note]} =
      CounterNotes.replace_scan_notes([
        %{
          surface: "groceries",
          kind: "usual_item_missing",
          title: "Oat milk?",
          body: "You always buy it.",
          proposed_run: %{
            "kind" => "add_item",
            "name" => "oat milk",
            "quantity" => nil,
            "unit" => nil
          }
        }
      ])

    assert Repo.get!(CounterNote, old.id).status == "expired"
    assert Repo.get!(CounterNote, keeper.id).status == "pending"
    assert new_note.kind == "usual_item_missing"
  end

  test "recently_ignored returns kind and title of recently ignored notes" do
    {:ok, note} =
      CounterNotes.create(%{
        surface: "home",
        kind: "freezer_fallback",
        title: "Frozen bolognese?",
        body: "b"
      })

    {:ok, _} = CounterNotes.ignore(note.id)

    assert [%{kind: "freezer_fallback", title: "Frozen bolognese?"}] =
             CounterNotes.recently_ignored(14)
  end
end
