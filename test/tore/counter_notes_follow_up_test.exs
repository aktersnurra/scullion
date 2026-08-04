defmodule Tore.CounterNotesFollowUpTest do
  use Tore.DataCase, async: false
  import Mox

  alias Tore.{Accounts, CounterNotes, Household}
  alias Tore.CounterNotes.CounterNote

  setup :verify_on_exit!
  setup :set_mox_from_context

  defp household_id, do: Household.get_household!().id

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp user_id do
    {:ok, {user, _code}} = Accounts.create_admin("Gustaf")
    user.id
  end

  describe "follow_up/2" do
    test "an add_item proposed_run adds the item directly and accepts the note" do
      stub(Tore.MockLLM, :text, fn _system, _user, _opts ->
        {:ok, %{"section" => "dairy"}, %{}}
      end)

      {:ok, note} =
        CounterNotes.create(%{
          surface: "groceries",
          kind: "usual_item_missing",
          title: "Oat milk?",
          body: "b",
          proposed_run: %{
            "kind" => "add_item",
            "name" => "oat milk",
            "quantity" => nil,
            "unit" => nil
          }
        })

      assert {:ok, _} =
               CounterNotes.follow_up(note.id, %{household_id: household_id(), user_id: user_id()})

      assert Repo.get!(CounterNote, note.id).status == "accepted"

      list_id = "shop_list:#{Date.to_iso8601(week_start(Date.utc_today()))}"
      {:ok, grocery_state} = Tore.Shop.load_list(list_id)

      assert grocery_state.items
             |> Map.values()
             |> Enum.any?(&(&1.name == "oat milk"))
    end

    test "a planner_command proposed_run dispatches a scoped run with counter_note_followup provenance" do
      {:ok, note} =
        CounterNotes.create(%{
          surface: "home",
          kind: "freezer_fallback",
          title: "Frozen bolognese?",
          body: "b",
          proposed_run: %{
            "kind" => "planner_command",
            "command" => "skip monday",
            "scoped_slot" => "mon_dinner"
          }
        })

      expect(Tore.MockLLM, :chat_with_tools, fn _sys, msgs, _tools, _opts ->
        user_msg = Enum.find(msgs, &(&1[:role] == "user" || &1["role"] == "user"))
        content = user_msg[:content] || user_msg["content"]
        assert content =~ "mon_dinner"
        assert content =~ "skip monday"

        {:ok, {:message, "done"},
         %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
      end)

      assert {:ok, _} =
               CounterNotes.follow_up(note.id, %{household_id: household_id(), user_id: user_id()})

      assert Repo.get!(CounterNote, note.id).status == "accepted"
    end

    test "a note without a proposed_run returns an error and stays pending" do
      {:ok, note} =
        CounterNotes.create(%{surface: "home", kind: "habit_pattern", title: "t", body: "b"})

      assert {:error, :no_proposed_run} =
               CounterNotes.follow_up(note.id, %{household_id: 1, user_id: 1})

      assert Repo.get!(CounterNote, note.id).status == "pending"
    end
  end
end
