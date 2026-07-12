defmodule Tore.Harness.ResolversTest do
  use Tore.DataCase, async: false

  import Mox

  alias Tore.Harness.Resolvers
  alias Tore.Harness.Handles.ResolvedRecipe
  alias Tore.Recipes

  setup :set_mox_from_context

  setup do
    # Recipes.create/1 fires an async Task that calls Tore.LLM.text to write
    # an image-gen prompt; stub it so the fire-and-forget task doesn't crash
    # under Mox's ownership checks.
    stub(Tore.MockLLM, :text, fn _system, _user, _opts ->
      {:ok, %{"prompt" => "A plate of food."}, %{}}
    end)

    {:ok, _} =
      Recipes.create(%{title: "Salmon pasta", base_servings: 2, instructions: "x"})

    {:ok, _} =
      Recipes.create(%{title: "Salmon soup", base_servings: 2, instructions: "x"})

    {:ok, _} =
      Recipes.create(%{title: "Chicken skewers", base_servings: 2, instructions: "x"})

    :ok
  end

  test "exact-ish title resolves with high confidence" do
    assert {:ok, %ResolvedRecipe{label: "Chicken skewers", source: :resolve_recipe} = h} =
             Resolvers.resolve_recipe("chicken skewers")

    assert h.confidence > 0.9
  end

  test "shared prefix is ambiguous" do
    assert {:ambiguous, handles} = Resolvers.resolve_recipe("salmon")
    assert length(handles) == 2
    assert Enum.all?(handles, &match?(%ResolvedRecipe{}, &1))
  end

  test "garbage is not found" do
    assert :not_found = Resolvers.resolve_recipe("zzzz qqqq")
  end
end
