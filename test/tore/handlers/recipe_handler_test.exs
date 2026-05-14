defmodule Tore.Handlers.RecipeHandlerTest do
  use Tore.DataCase, async: false
  import Mox
  alias Tore.Handlers.RecipeHandler

  setup :verify_on_exit!

  @ld_json_html """
  <html><head>
  <script type="application/ld+json">
  {"@type": "Recipe", "name": "Scraped Pasta", "recipeIngredient": ["pasta", "sauce"]}
  </script>
  </head><body></body></html>
  """

  @plain_html "<html><body><h1>A recipe page</h1></body></html>"

  describe "scrape_and_create/1" do
    test "uses Parser result when JSON-LD found" do
      Tore.MockHTTP
      |> expect(:fetch, fn "https://example.com/recipe" -> {:ok, @ld_json_html} end)

      assert {:ok, recipe} = RecipeHandler.scrape_and_create("https://example.com/recipe")
      assert recipe.title == "Scraped Pasta"
      assert recipe.source_url == "https://example.com/recipe"
    end

    test "falls back to LLM when Parser returns not_found" do
      Tore.MockHTTP
      |> expect(:fetch, fn "https://example.com/plain" -> {:ok, @plain_html} end)

      Tore.MockLLM
      |> expect(:extract_recipe_from_html, fn _html, _locale ->
        {:ok, %{title: "LLM Recipe", ingredients: []}}
      end)

      assert {:ok, recipe} = RecipeHandler.scrape_and_create("https://example.com/plain")
      assert recipe.title == "LLM Recipe"
    end

    test "propagates HTTP error" do
      Tore.MockHTTP
      |> expect(:fetch, fn _ -> {:error, :timeout} end)

      assert {:error, :timeout} = RecipeHandler.scrape_and_create("https://example.com/bad")
    end
  end
end
