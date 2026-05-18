defmodule Tore.CounterNotesTest do
  use Tore.DataCase, async: true
  alias Tore.CounterNotes

  test "list_for_surface/1 returns pending notes for the given surface only" do
    {:ok, _} = CounterNotes.create(%{
      surface: "home", kind: "deal_opportunity",
      title: "Chicken deal", body: "ICA has chicken thighs 20% off."
    })
    {:ok, _} = CounterNotes.create(%{
      surface: "pantry", kind: "pantry_assumption",
      title: "Rice", body: "Probably have rice."
    })

    home_notes = CounterNotes.list_for_surface("home")
    assert length(home_notes) == 1
    assert hd(home_notes).surface == "home"
  end

  test "ignore/1 removes note from surface listing" do
    {:ok, note} = CounterNotes.create(%{
      surface: "home", kind: "deal_opportunity",
      title: "Test", body: "Test."
    })
    {:ok, _} = CounterNotes.ignore(note.id)
    assert CounterNotes.list_for_surface("home") == []
  end

  test "accept/1 sets status to accepted" do
    {:ok, note} = CounterNotes.create(%{
      surface: "home", kind: "habit_pattern",
      title: "Thursday", body: "You often skip Thursday."
    })
    {:ok, updated} = CounterNotes.accept(note.id)
    assert updated.status == "accepted"
  end

  test "expire_stale/0 marks expired notes" do
    past = DateTime.add(DateTime.utc_now(), -3600, :second)
    {:ok, _} = CounterNotes.create(%{
      surface: "week", kind: "plan_repair",
      title: "Fragile", body: "Week looks fragile.",
      expires_at: past
    })
    {count, _} = CounterNotes.expire_stale()
    assert count == 1
    assert CounterNotes.list_for_surface("week") == []
  end
end
