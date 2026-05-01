defmodule Scullion.Handlers.RecipeHandler do
  @http Application.compile_env(:scullion, :http_client)
  @llm Application.compile_env(:scullion, :llm_client)

  def scrape_and_create(url) do
    with {:ok, html} <- @http.fetch(url),
         {:ok, attrs} <- parse_or_extract(html) do
      Scullion.Recipes.create(Map.put(attrs, :source_url, url))
    end
  end

  defp parse_or_extract(html) do
    # Try structured parser first, fall back to LLM extraction
    with {:error, _} <- Scullion.Recipes.Parser.parse_html(html) do
      @llm.extract_recipe_from_html(html)
    end
  end
end
