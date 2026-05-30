defmodule Tore.AiOperationsTest do
  use Tore.DataCase, async: false

  test "log/1 and find_by_correlation/1 round-trip" do
    correlation_id = "test-#{System.unique_integer()}"

    assert {:ok, op} =
             Tore.AiOperations.log(%{
               correlation_id: correlation_id,
               kind: "chat",
               payload: "What's for dinner?",
               result: "Pasta"
             })

    assert op.kind == "chat"
    found = Tore.AiOperations.find_by_correlation(correlation_id)
    assert found.id == op.id
    assert found.result == "Pasta"
  end

  test "logs multiple steps under one correlation_id" do
    cid = "test-cid-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             Tore.AiOperations.log(%{
               correlation_id: cid,
               kind: "planner_agent.turn",
               step_index: 0,
               payload: "user msg",
               result: "tool_calls"
             })

    assert {:ok, _} =
             Tore.AiOperations.log(%{
               correlation_id: cid,
               kind: "planner_agent.turn",
               step_index: 1,
               payload: "tool result",
               result: "final"
             })

    rows = Tore.AiOperations.list_by_correlation(cid)
    assert length(rows) == 2
    assert Enum.map(rows, & &1.step_index) == [0, 1]
  end

  test "rejects duplicate (correlation_id, step_index)" do
    cid = "dup-cid-#{System.unique_integer([:positive])}"
    {:ok, _} = Tore.AiOperations.log(%{correlation_id: cid, kind: "k", step_index: 0})

    assert {:error, %Ecto.Changeset{}} =
             Tore.AiOperations.log(%{correlation_id: cid, kind: "k", step_index: 0})
  end
end
