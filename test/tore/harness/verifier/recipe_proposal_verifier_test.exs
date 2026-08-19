defmodule Tore.Harness.Verifier.RecipeProposalVerifierTest do
  use ExUnit.Case, async: true

  alias Tore.Harness.Artifact.RecipeProposal
  alias Tore.Harness.Verifier.RecipeProposalVerifier

  defp proposal(overrides \\ %{}) do
    base = %RecipeProposal{
      title: "Miso Ramen",
      instructions: "Simmer the broth. Cook the noodles.",
      base_servings: 4,
      ingredients: [
        %{name: "miso paste", quantity: "2", unit: "msk"},
        %{name: "ramen noodles", quantity: "4", unit: nil}
      ],
      source: :generation,
      source_recipe_id: 7,
      instruction: "simpler"
    }

    struct!(base, overrides)
  end

  test "a complete proposal passes" do
    assert RecipeProposalVerifier.verify(proposal(), %{}) == :ok
  end

  test "a missing title fails" do
    assert RecipeProposalVerifier.verify(proposal(%{title: ""}), %{}) ==
             {:fail, :missing_title, :reject}
  end

  test "no ingredients fails" do
    assert RecipeProposalVerifier.verify(proposal(%{ingredients: []}), %{}) ==
             {:fail, :no_ingredients, :reject}
  end

  test "an empty ingredient name fails" do
    ingredients = [
      %{name: "miso paste", quantity: "2", unit: "msk"},
      %{name: "  ", quantity: nil, unit: nil}
    ]

    assert RecipeProposalVerifier.verify(proposal(%{ingredients: ingredients}), %{}) ==
             {:fail, :empty_ingredient_name, :reject}
  end

  test "missing instructions fails" do
    assert RecipeProposalVerifier.verify(proposal(%{instructions: nil}), %{}) ==
             {:fail, :missing_instructions, :reject}
  end

  test "zero servings fails" do
    assert RecipeProposalVerifier.verify(proposal(%{base_servings: 0}), %{}) ==
             {:fail, :invalid_servings, :reject}
  end

  test "nil servings fails" do
    assert RecipeProposalVerifier.verify(proposal(%{base_servings: nil}), %{}) ==
             {:fail, :invalid_servings, :reject}
  end

  test "a near-duplicate of an existing catalog recipe fails" do
    existing = [
      %{
        title: "miso ramen",
        ingredient_names: ["miso paste", "ramen noodles"]
      }
    ]

    assert RecipeProposalVerifier.verify(proposal(), %{existing_recipes: existing}) ==
             {:fail, :near_duplicate, :reject}
  end

  test "a same-title recipe with different ingredients is not a duplicate" do
    existing = [%{title: "Miso Ramen", ingredient_names: ["butter", "flour", "sugar", "eggs"]}]

    assert RecipeProposalVerifier.verify(proposal(), %{existing_recipes: existing}) == :ok
  end

  test "a different-title recipe with the same ingredients is not a duplicate" do
    existing = [%{title: "Tonkotsu Ramen", ingredient_names: ["miso paste", "ramen noodles"]}]

    assert RecipeProposalVerifier.verify(proposal(), %{existing_recipes: existing}) == :ok
  end

  test "title comparison ignores case and surrounding whitespace" do
    existing = [%{title: "  MISO RAMEN ", ingredient_names: ["miso paste", "ramen noodles"]}]

    assert RecipeProposalVerifier.verify(proposal(), %{existing_recipes: existing}) ==
             {:fail, :near_duplicate, :reject}
  end
end
