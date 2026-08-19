defmodule Tore.Harness.Verifier.RecipeProposalVerifier do
  @moduledoc """
  Deterministic verifier for `RecipeProposal` (SPEC §A.5). Pure: no writes,
  no model calls.

  Checks:
    * title present
    * at least one ingredient, none with an empty name
    * instructions present
    * servings positive
    * not a near-duplicate of an existing catalog recipe

  Near-duplicate means *both* the same normalised title *and* a majority of
  ingredients in common — either alone is a legitimate new recipe ("Miso
  Ramen" made a different way; a second dish from the same pantry staples).

  The catalog is passed in via `ctx[:existing_recipes]` as a list of
  `%{title: String.t(), ingredient_names: [String.t()]}`, so the verifier
  itself does no IO. An absent key means "nothing to compare against".

  Repair action is `:reject` — the user edits the proposal on the
  `:needs_user` card before re-submitting.
  """

  alias Tore.Harness.Artifact.RecipeProposal

  @overlap_threshold 0.6

  @type fail_code ::
          :missing_title
          | :no_ingredients
          | :empty_ingredient_name
          | :missing_instructions
          | :invalid_servings
          | :near_duplicate
  @type repair_action :: :reject

  @spec verify(RecipeProposal.t(), map()) :: :ok | {:fail, fail_code(), repair_action()}
  def verify(%RecipeProposal{} = proposal, ctx \\ %{}) do
    with :ok <- check_title(proposal),
         :ok <- check_ingredients(proposal),
         :ok <- check_instructions(proposal),
         :ok <- check_servings(proposal) do
      check_duplicate(proposal, Map.get(ctx, :existing_recipes, []))
    end
  end

  defp check_title(%RecipeProposal{title: t}) when is_binary(t) do
    if String.trim(t) == "", do: {:fail, :missing_title, :reject}, else: :ok
  end

  defp check_title(_), do: {:fail, :missing_title, :reject}

  defp check_ingredients(%RecipeProposal{ingredients: []}), do: {:fail, :no_ingredients, :reject}

  defp check_ingredients(%RecipeProposal{ingredients: ingredients}) when is_list(ingredients) do
    if Enum.any?(ingredients, &blank_name?/1) do
      {:fail, :empty_ingredient_name, :reject}
    else
      :ok
    end
  end

  defp check_ingredients(_), do: {:fail, :no_ingredients, :reject}

  defp blank_name?(ing) do
    name = ing[:name] || ing["name"]
    not is_binary(name) or String.trim(name) == ""
  end

  defp check_instructions(%RecipeProposal{instructions: i}) when is_binary(i) do
    if String.trim(i) == "", do: {:fail, :missing_instructions, :reject}, else: :ok
  end

  defp check_instructions(_), do: {:fail, :missing_instructions, :reject}

  defp check_servings(%RecipeProposal{base_servings: s}) when is_integer(s) and s > 0, do: :ok
  defp check_servings(_), do: {:fail, :invalid_servings, :reject}

  defp check_duplicate(_proposal, []), do: :ok

  defp check_duplicate(%RecipeProposal{} = proposal, existing) do
    title = normalise(proposal.title)
    names = ingredient_name_set(proposal.ingredients)

    duplicate? =
      Enum.any?(existing, fn candidate ->
        normalise(candidate_title(candidate)) == title and
          overlap(names, MapSet.new(candidate_names(candidate), &normalise/1)) >=
            @overlap_threshold
      end)

    if duplicate?, do: {:fail, :near_duplicate, :reject}, else: :ok
  end

  defp candidate_title(%{title: t}), do: t
  defp candidate_title(%{"title" => t}), do: t

  defp candidate_names(%{ingredient_names: n}), do: n
  defp candidate_names(%{"ingredient_names" => n}), do: n

  defp ingredient_name_set(ingredients) do
    ingredients
    |> Enum.map(fn ing -> normalise(ing[:name] || ing["name"]) end)
    |> MapSet.new()
  end

  # Fraction of the proposal's ingredients that the candidate also has.
  defp overlap(proposed, existing) do
    if MapSet.size(proposed) == 0 do
      0.0
    else
      MapSet.intersection(proposed, existing)
      |> MapSet.size()
      |> Kernel./(MapSet.size(proposed))
    end
  end

  defp normalise(nil), do: ""
  defp normalise(s) when is_binary(s), do: s |> String.trim() |> String.downcase()
end
