defmodule Tore.Harness.RunReceiptsTest do
  use Tore.DataCase, async: false

  alias Tore.Harness.{Run, RunReceipts, UndoPayload}
  alias Tore.Harness.Run.{Commands, Events, State}
  alias Tore.Harness.Artifact.{PantryBeliefUpdate, PlanDiff, RunSummary}

  defp seed_applied_run(household_id, artifacts) do
    sid = Run.next_stream_id()

    {:ok, [opened]} =
      Run.decide(
        %Commands.Open{
          household_id: household_id,
          kind: "planner_command_run",
          surface: :plan,
          started_by: "user",
          user_id: 1,
          input: %{command: "do thing"}
        },
        %State.Draft{stream_id: sid}
      )

    artifact_events = Enum.map(artifacts, &%Events.ArtifactAdded{artifact: &1})

    payload = UndoPayload.from_artifacts(artifacts)
    committed = %Events.Committed{at: ~U[2026-06-28 12:00:00Z], undo_payload: payload}

    :ok = Run.append(sid, [opened] ++ artifact_events ++ [committed])
    sid
  end

  defp plan_diff do
    %PlanDiff{
      plan_stream_id: "plan-h1-w1",
      week_start: ~D[2026-06-22],
      events: [
        %{
          slot_key: "2026-06-23-dinner",
          event_type: "RecipeAssigned",
          payload: %{"label" => "Pasta"},
          rationale: ["uses leftover salmon"]
        }
      ]
    }
  end

  defp pantry_update do
    %PantryBeliefUpdate{
      items: [
        %{
          name: "olive oil",
          change: :added,
          quantity: nil,
          unit: nil,
          category: nil,
          provenance: "receipt",
          last_seen_at: ~U[2026-06-28 12:00:00Z]
        }
      ]
    }
  end

  describe "get/1" do
    test "returns a receipt for an Applied run" do
      sid = seed_applied_run(1, [plan_diff()])

      assert {:ok, receipt} = RunReceipts.get(sid)
      assert receipt.stream_id == sid
      assert receipt.household_id == 1
      assert receipt.applied_at == ~U[2026-06-28 12:00:00Z]
      assert receipt.reverted_at == nil
      assert %UndoPayload{kind: :event_sourced} = receipt.undo_payload
    end

    test "returns {:error, :not_applied} for a Running run" do
      sid = Run.next_stream_id()

      {:ok, [opened]} =
        Run.decide(
          %Commands.Open{
            household_id: 1,
            kind: "planner_command_run",
            surface: :plan,
            started_by: "user",
            user_id: 1,
            input: %{}
          },
          %State.Draft{stream_id: sid}
        )

      :ok = Run.append(sid, [opened])
      assert {:error, :not_applied} = RunReceipts.get(sid)
    end

    test "returns {:error, :not_found} for an unknown stream" do
      assert {:error, :not_found} = RunReceipts.get("run-never-seen")
    end
  end

  describe "to_diff_rows/1" do
    test "projects a PlanDiff into one DiffRow per slot event" do
      rows = RunReceipts.to_diff_rows([plan_diff()])
      assert [row] = rows
      assert row.surface == :plan
      assert row.op == :added
      assert row.label =~ "Pasta"
    end

    test "projects a PantryBeliefUpdate :added item into a pantry DiffRow with op :added" do
      rows = RunReceipts.to_diff_rows([pantry_update()])
      assert [row] = rows
      assert row.surface == :pantry
      assert row.op == :added
      assert row.label =~ "olive oil"
    end

    test "ignores RunSummary artifacts (they describe, not change)" do
      summary = %RunSummary{counts: %{}, outcome: :applied}
      rows = RunReceipts.to_diff_rows([summary])
      assert rows == []
    end

    test "combines multiple artifacts in order" do
      rows = RunReceipts.to_diff_rows([plan_diff(), pantry_update()])
      assert length(rows) == 2
      assert Enum.map(rows, & &1.surface) == [:plan, :pantry]
    end
  end

  describe "list_for_household/2" do
    test "returns Applied receipts for the given household, newest first" do
      sid1 = seed_applied_run(7, [plan_diff()])
      sid2 = seed_applied_run(7, [pantry_update()])
      _other = seed_applied_run(8, [plan_diff()])

      receipts = RunReceipts.list_for_household(7)
      stream_ids = Enum.map(receipts, & &1.stream_id)

      assert sid1 in stream_ids
      assert sid2 in stream_ids
      assert length(receipts) == 2
    end
  end

  describe "revert/1" do
    test "transitions an Applied run to Reverted" do
      sid = seed_applied_run(1, [plan_diff()])

      assert :ok = RunReceipts.revert(sid)
      {:ok, state} = Run.load(sid)
      assert %State.Reverted{} = state
    end

    test "returns {:error, :irreversible} when undo_payload is irreversible" do
      cost = %Tore.Harness.Artifact.CostEntry{
        store_name: "ICA",
        date: ~D[2026-06-28],
        total: Decimal.new("10"),
        line_items: []
      }

      sid = seed_applied_run(1, [cost])

      assert {:error, :irreversible} = RunReceipts.revert(sid)
      {:ok, state} = Run.load(sid)
      assert %State.Applied{} = state
    end

    test "returns {:error, :not_applied} for a run that is not Applied" do
      assert {:error, :not_found} = RunReceipts.revert("run-never-seen")
    end
  end
end
