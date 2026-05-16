defmodule Tore.Handlers.RecipeHandler do
  import Ecto.Query
  @http Application.compile_env(:tore, :http_client)
  @llm Application.compile_env(:tore, :llm_client)
  @image_gen Application.compile_env(:tore, :image_gen_client)

  @spec scrape_and_create(String.t(), String.t() | nil) ::
          {:ok, Tore.Recipes.Recipe.t()} | {:error, term()}
  def scrape_and_create(url, locale \\ nil) do
    with {:ok, html} <- @http.fetch(url),
         {:ok, attrs} <- parse_or_extract(html, locale) do
      Tore.Recipes.create(Map.put(attrs, :source_url, url))
    end
  end

  @spec generate_image(Tore.Recipes.Recipe.t(), String.t() | nil) :: :ok | {:error, term()}
  def generate_image(recipe, image_url) do
    uploads_dir = Path.join(Application.fetch_env!(:tore, :uploads_dir), "recipes")
    File.mkdir_p!(uploads_dir)

    with {:ok, binary} <- fetch_or_generate(recipe, image_url),
         path = Path.join(uploads_dir, "#{recipe.id}.jpg"),
         :ok <- File.write(path, binary) do
      Tore.Repo.update_all(
        from(r in Tore.Recipes.Recipe, where: r.id == ^recipe.id),
        set: [image_path: "/uploads/recipes/#{recipe.id}.jpg"]
      )

      :ok
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp parse_or_extract(html, locale) do
    with {:error, :not_found} <- Tore.Recipes.Parser.parse_html(html) do
      @llm.extract_recipe_from_html(html, locale)
    end
  end

  defp fetch_or_generate(_recipe, image_url) when is_binary(image_url) and image_url != "" do
    @http.fetch(image_url)
  end

  defp fetch_or_generate(recipe, _image_url) do
    @image_gen.generate_food_image(recipe.title, recipe.instructions)
  end
end
