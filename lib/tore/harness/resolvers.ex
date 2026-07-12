defmodule Tore.Harness.Resolvers do
  @moduledoc """
  Resolver tools (SPEC.md §A.6.2): natural-language reference → typed handle.
  V1 implements recipes only; slot references are covered by structural
  slot keys and direct-touch handles. Pure read — no writes, no LLM calls.
  """

  alias Tore.Harness.Handles
  alias Tore.Recipes

  @accept 0.7
  @floor 0.45
  @clear_gap 0.1

  def resolve_recipe(query) when is_binary(query) do
    q = normalize(query)

    scored =
      Recipes.list()
      |> Enum.map(fn r -> {similarity(q, normalize(r.title)), r} end)
      |> Enum.sort_by(fn {s, _} -> s end, :desc)

    case scored do
      [] ->
        :not_found

      [{best, _} | _] when best < @floor ->
        :not_found

      [{best, r}] when best >= @accept ->
        {:ok, to_handle(r, best)}

      [{best, r}, {second, _} | _] when best >= @accept and best - second >= @clear_gap ->
        {:ok, to_handle(r, best)}

      plausible ->
        {:ambiguous,
         plausible
         |> Enum.take_while(fn {s, _} -> s >= @floor end)
         |> Enum.take(3)
         |> Enum.map(fn {s, r} -> to_handle(r, s) end)}
    end
  end

  defp to_handle(recipe, score),
    do: Handles.recipe(recipe.id, recipe.title, :resolve_recipe, Float.round(score, 2))

  defp similarity(a, b) do
    jaro = String.jaro_distance(a, b)
    if String.contains?(b, a), do: max(jaro, 0.65), else: jaro
  end

  defp normalize(s), do: s |> String.downcase() |> String.trim()
end
