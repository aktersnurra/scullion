defmodule Tore.Adapters.OpenRouterSubstitutionTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "suggest_substitution mock returns suggestion map" do
    Tore.MockLLM
    |> expect(:suggest_substitution, fn "crème fraîche", _recipe ->
      {:ok, %{suggestion: "Use Greek yogurt + a little lemon.", updated_steps: nil}}
    end)

    assert {:ok, %{suggestion: suggestion}} =
             Tore.MockLLM.suggest_substitution("crème fraîche", "Salmon with sauce")

    assert String.contains?(suggestion, "yogurt")
  end
end
