defmodule Tore.Capture.RouterTest do
  use Tore.DataCase, async: false
  import Mox
  setup :verify_on_exit!

  alias Tore.Capture.Router
  alias Tore.Harness.Run
  alias Tore.Harness.Run.State
  alias Tore.Harness.Artifact.RunBundle

  describe "route/4 with set_plan_slot" do
    test "wraps the turn in a :capture_turn_run that bundles the set_plan_slot child" do
      {:ok, recipe} =
        %Tore.Recipes.Recipe{title: "Pizza", recipe_type: :meal}
        |> Tore.Repo.insert()

      # Turn 1: model emits a set_plan_slot tool call.
      # Turn 2: model replies in plain text.
      tool_call = %{
        id: "call_1",
        name: "set_plan_slot",
        args: %{"date" => "2026-06-23", "recipe_id" => recipe.id, "servings" => 4}
      }

      expect(Tore.MockLLM, :chat_with_tools, 2, fn _sys, _msgs, _tools, _opts ->
        case Process.get(:turn_count, 0) do
          0 ->
            Process.put(:turn_count, 1)
            {:ok, {:tool_calls, [tool_call]},
             %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}

          _ ->
            {:ok, {:message, "Done."},
             %{prompt_tokens: 1, completion_tokens: 1, cost_usd: Decimal.new(0)}}
        end
      end)

      ctx = %{household_id: 1, user_id: 42, locale: "en"}
      assert {:ok, bubbles} = Router.route("plan pizza tuesday", [], ctx)

      # The user-facing bubbles still flow through.
      assert Enum.any?(bubbles, fn b -> Map.get(b, :text) =~ "Pizza" end)

      # A capture_turn_run Run was opened, bundled, and applied with the child sid.
      [parent_run] = list_applied_turn_runs()
      assert %State.Applied{kind: "capture_turn_run"} = parent_run
      assert [%RunBundle{child_stream_ids: [child_sid]}] = parent_run.artifacts

      {:ok, %State.Applied{kind: "set_plan_slot_run"}} = Run.load(child_sid)
    end

    defp list_applied_turn_runs do
      import Ecto.Query
      alias Tore.EventStore.Event
      alias Tore.Repo

      from(e in Event,
        where: e.stream_type == "run" and e.event_type == "Opened",
        where: fragment("json_extract(?, '$.kind') = ?", e.data, "capture_turn_run"),
        select: e.stream_id
      )
      |> Repo.all()
      |> Enum.flat_map(fn sid ->
        case Run.load(sid) do
          {:ok, %State.Applied{} = s} -> [s]
          _ -> []
        end
      end)
    end
  end
end
