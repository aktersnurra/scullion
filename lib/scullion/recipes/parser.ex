defmodule Scullion.Recipes.Parser do
  @moduledoc false

  @spec parse_html(String.t()) :: {:ok, map()} | {:error, :not_found}
  def parse_html(html) do
    with {:error, :not_found} <- parse_json_ld(html) do
      parse_microdata(html)
    end
  end

  # ── JSON-LD ────────────────────────────────────────────────────────────────

  defp parse_json_ld(html) do
    {:ok, doc} = Floki.parse_document(html)

    doc
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.find_value(:error, fn node ->
      text = Floki.text(node)

      case Jason.decode(text) do
        {:ok, data} -> find_recipe_in_ld(data)
        _ -> nil
      end
    end)
    |> case do
      :error -> {:error, :not_found}
      attrs -> {:ok, attrs}
    end
  end

  defp find_recipe_in_ld(data) when is_list(data) do
    Enum.find_value(data, &find_recipe_in_ld/1)
  end

  defp find_recipe_in_ld(%{"@type" => type} = data) when is_binary(type) do
    if String.contains?(type, "Recipe"), do: extract_ld_attrs(data)
  end

  defp find_recipe_in_ld(%{"@graph" => graph}) when is_list(graph) do
    find_recipe_in_ld(graph)
  end

  defp find_recipe_in_ld(_), do: nil

  defp extract_ld_attrs(data) do
    %{
      title: Map.get(data, "name"),
      description: Map.get(data, "description"),
      instructions: extract_ld_instructions(data),
      prep_time_minutes: parse_duration(Map.get(data, "prepTime")),
      cook_time_minutes: parse_duration(Map.get(data, "cookTime")),
      base_servings: extract_ld_servings(data),
      ingredients: extract_ld_ingredients(data),
      image_url: extract_ld_image(data)
    }
    |> reject_nils()
  end

  defp extract_ld_instructions(%{"recipeInstructions" => instructions}) when is_list(instructions) do
    instructions
    |> Enum.map(fn
      %{"text" => text} -> text
      text when is_binary(text) -> text
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp extract_ld_instructions(%{"recipeInstructions" => text}) when is_binary(text), do: text
  defp extract_ld_instructions(_), do: nil

  defp extract_ld_servings(%{"recipeYield" => yield}) when is_integer(yield), do: yield

  defp extract_ld_servings(%{"recipeYield" => yield}) when is_binary(yield) do
    case Integer.parse(yield) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp extract_ld_servings(%{"recipeYield" => [first | _]}), do: extract_ld_servings(%{"recipeYield" => first})
  defp extract_ld_servings(_), do: nil

  defp extract_ld_ingredients(%{"recipeIngredient" => list}) when is_list(list) do
    Enum.map(list, fn text -> %{name: text, quantity: nil, unit: nil} end)
  end

  defp extract_ld_ingredients(_), do: []

  defp extract_ld_image(%{"image" => url}) when is_binary(url), do: url
  defp extract_ld_image(%{"image" => %{"url" => url}}), do: url
  defp extract_ld_image(%{"image" => [url | _]}) when is_binary(url), do: url
  defp extract_ld_image(%{"image" => [%{"url" => url} | _]}), do: url
  defp extract_ld_image(_), do: nil

  # ── Microdata ──────────────────────────────────────────────────────────────

  defp parse_microdata(html) do
    {:ok, doc} = Floki.parse_document(html)

    node =
      Floki.find(doc, "[itemtype*='schema.org/Recipe']")
      |> List.first()

    case node do
      nil ->
        {:error, :not_found}

      _ ->
        attrs =
          %{
            title: itemprop_text(doc, node, "name"),
            description: itemprop_text(doc, node, "description"),
            instructions: itemprop_text(doc, node, "recipeInstructions"),
            prep_time_minutes: itemprop_attr(doc, node, "prepTime", "content") |> parse_duration(),
            cook_time_minutes: itemprop_attr(doc, node, "cookTime", "content") |> parse_duration(),
            base_servings: itemprop_text(doc, node, "recipeYield") |> parse_integer(),
            ingredients: extract_microdata_ingredients(doc, node),
            image_url: itemprop_attr(doc, node, "image", "src")
          }
          |> reject_nils()

        if Map.has_key?(attrs, :title), do: {:ok, attrs}, else: {:error, :not_found}
    end
  end

  defp itemprop_text(_doc, node, prop) do
    case Floki.find(node, "[itemprop='#{prop}']") do
      [] -> nil
      [first | _] -> first |> Floki.text() |> String.trim() |> nilify()
    end
  end

  defp itemprop_attr(_doc, node, prop, attr) do
    case Floki.find(node, "[itemprop='#{prop}']") do
      [] -> nil
      [first | _] -> Floki.attribute(first, attr) |> List.first()
    end
  end

  defp extract_microdata_ingredients(_doc, node) do
    Floki.find(node, "[itemprop='recipeIngredient']")
    |> Enum.map(fn el -> %{name: Floki.text(el) |> String.trim(), quantity: nil, unit: nil} end)
    |> Enum.reject(fn %{name: n} -> n == "" end)
  end

  # ── Duration parsing ───────────────────────────────────────────────────────

  # Parses ISO 8601 durations like PT1H30M, PT45M, P0DT1H
  @spec parse_duration(String.t() | nil) :: integer() | nil
  def parse_duration(nil), do: nil
  def parse_duration(""), do: nil

  def parse_duration(duration) when is_binary(duration) do
    hours = Regex.run(~r/(\d+)H/, duration) |> extract_match()
    minutes = Regex.run(~r/(\d+)M/, duration) |> extract_match()

    case {hours, minutes} do
      {nil, nil} -> nil
      _ -> (hours || 0) * 60 + (minutes || 0)
    end
  end

  defp extract_match([_, n]), do: String.to_integer(n)
  defp extract_match(_), do: nil

  defp parse_integer(nil), do: nil

  defp parse_integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp reject_nils(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end
end
