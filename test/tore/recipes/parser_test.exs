defmodule Tore.Recipes.ParserTest do
  use ExUnit.Case, async: true
  alias Tore.Recipes.Parser

  @ld_json_html """
  <html><head>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Recipe",
    "name": "Pasta Carbonara",
    "description": "Classic Roman pasta",
    "recipeIngredient": ["200g spaghetti", "100g guanciale", "2 eggs"],
    "recipeInstructions": [
      {"@type": "HowToStep", "text": "Boil pasta."},
      {"@type": "HowToStep", "text": "Fry guanciale."}
    ],
    "prepTime": "PT10M",
    "cookTime": "PT20M",
    "recipeYield": "2",
    "image": "https://example.com/carbonara.jpg"
  }
  </script>
  </head><body></body></html>
  """

  @ld_json_no_recipe """
  <html><head>
  <script type="application/ld+json">{"@type": "WebPage", "name": "Test"}</script>
  </head><body></body></html>
  """

  @ld_json_graph """
  <html><head>
  <script type="application/ld+json">
  {
    "@graph": [
      {"@type": "WebPage"},
      {"@type": "Recipe", "name": "Graph Soup", "recipeIngredient": ["water"]}
    ]
  }
  </script>
  </head><body></body></html>
  """

  @microdata_html """
  <html><body>
  <div itemscope itemtype="http://schema.org/Recipe">
    <span itemprop="name">Microdata Stew</span>
    <span itemprop="recipeIngredient">potatoes</span>
    <span itemprop="recipeIngredient">carrots</span>
    <meta itemprop="prepTime" content="PT15M" />
    <meta itemprop="cookTime" content="PT45M" />
    <span itemprop="recipeYield">4</span>
  </div>
  </body></html>
  """

  @no_recipe_html "<html><body><p>Nothing here</p></body></html>"

  describe "parse_html/1 with JSON-LD" do
    test "extracts title" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.title == "Pasta Carbonara"
    end

    test "extracts description" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.description == "Classic Roman pasta"
    end

    test "joins instruction list into text" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.instructions =~ "Boil pasta."
      assert attrs.instructions =~ "Fry guanciale."
    end

    test "parses ISO 8601 duration PT10M → 10" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.prep_time_minutes == 10
    end

    test "parses ISO 8601 duration PT20M → 20" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.cook_time_minutes == 20
    end

    test "parses recipeYield as integer" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.base_servings == 2
    end

    test "extracts ingredients as list" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert length(attrs.ingredients) == 3
      assert hd(attrs.ingredients).name == "200g spaghetti"
    end

    test "extracts image URL" do
      {:ok, attrs} = Parser.parse_html(@ld_json_html)
      assert attrs.image_url == "https://example.com/carbonara.jpg"
    end

    test "returns :not_found when no Recipe type in ld+json" do
      assert {:error, :not_found} = Parser.parse_html(@ld_json_no_recipe)
    end

    test "finds Recipe inside @graph" do
      {:ok, attrs} = Parser.parse_html(@ld_json_graph)
      assert attrs.title == "Graph Soup"
    end
  end

  describe "parse_html/1 with microdata" do
    test "extracts title from itemprop=name" do
      {:ok, attrs} = Parser.parse_html(@microdata_html)
      assert attrs.title == "Microdata Stew"
    end

    test "extracts ingredient list" do
      {:ok, attrs} = Parser.parse_html(@microdata_html)
      names = Enum.map(attrs.ingredients, & &1.name)
      assert "potatoes" in names
      assert "carrots" in names
    end

    test "parses prep and cook times" do
      {:ok, attrs} = Parser.parse_html(@microdata_html)
      assert attrs.prep_time_minutes == 15
      assert attrs.cook_time_minutes == 45
    end

    test "parses recipeYield" do
      {:ok, attrs} = Parser.parse_html(@microdata_html)
      assert attrs.base_servings == 4
    end
  end

  describe "parse_html/1 with neither" do
    test "returns {:error, :not_found}" do
      assert {:error, :not_found} = Parser.parse_html(@no_recipe_html)
    end
  end

  describe "parse_duration/1" do
    test "PT1H30M → 90" do
      assert Parser.parse_duration("PT1H30M") == 90
    end

    test "PT45M → 45" do
      assert Parser.parse_duration("PT45M") == 45
    end

    test "PT2H → 120" do
      assert Parser.parse_duration("PT2H") == 120
    end

    test "nil → nil" do
      assert Parser.parse_duration(nil) == nil
    end

    test "empty string → nil" do
      assert Parser.parse_duration("") == nil
    end
  end
end
