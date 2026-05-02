defmodule Scullion.Handlers.RecipeHandler do
  import Ecto.Query
  @http Application.compile_env(:scullion, :http_client)
  @llm Application.compile_env(:scullion, :llm_client)
  @image_gen Application.compile_env(:scullion, :image_gen_client)

  @uploads_dir Path.join([:code.priv_dir(:scullion), "static", "uploads", "recipes"])

  @spec scrape_and_create(String.t()) :: {:ok, Scullion.Recipes.Recipe.t()} | {:error, term()}
  def scrape_and_create(url) do
    with {:ok, html} <- @http.fetch(url),
         {:ok, attrs} <- parse_or_extract(html) do
      Scullion.Recipes.create(Map.put(attrs, :source_url, url))
    end
  end

  @spec generate_image(Scullion.Recipes.Recipe.t(), String.t() | nil) :: :ok | {:error, term()}
  def generate_image(recipe, image_url) do
    File.mkdir_p!(@uploads_dir)

    with {:ok, binary} <- fetch_or_generate(recipe, image_url),
         path = image_path(recipe.id),
         :ok <- File.write(path, binary) do
      Scullion.Repo.update_all(
        from(r in Scullion.Recipes.Recipe, where: r.id == ^recipe.id),
        set: [image_path: "/uploads/recipes/#{recipe.id}.jpg"]
      )

      :ok
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp parse_or_extract(html) do
    with {:error, :not_found} <- Scullion.Recipes.Parser.parse_html(html) do
      @llm.extract_recipe_from_html(html)
    end
  end

  defp fetch_or_generate(_recipe, image_url) when is_binary(image_url) and image_url != "" do
    @http.fetch(image_url)
  end

  defp fetch_or_generate(recipe, _image_url) do
    ingredient_names =
      (recipe.recipe_ingredients || [])
      |> Enum.map(& &1.ingredient.name)
      |> Enum.take(5)

    @image_gen.generate_food_image(recipe.title, ingredient_names)
  end

  defp image_path(id), do: Path.join(@uploads_dir, "#{id}.jpg")
end
