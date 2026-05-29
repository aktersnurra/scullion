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

  test "log/1 returns error on duplicate correlation_id" do
    correlation_id = "dup-#{System.unique_integer()}"
    assert {:ok, _} = Tore.AiOperations.log(%{correlation_id: correlation_id, kind: "chat"})
    assert {:error, changeset} = Tore.AiOperations.log(%{correlation_id: correlation_id, kind: "chat"})
    assert {:correlation_id, _} = hd(changeset.errors)
  end
end
