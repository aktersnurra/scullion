defmodule Scullion.RecipesTest do
  use Scullion.DataCase, async: false
  alias Scullion.Recipes

  defp recipe_attrs(overrides \\ %{}) do
    Map.merge(%{title: "Test Recipe", recipe_type: :meal}, overrides)
  end

  describe "create/1" do
    test "inserts a basic recipe" do
      assert {:ok, recipe} = Recipes.create(recipe_attrs())
      assert recipe.title == "Test Recipe"
      assert recipe.recipe_type == :meal
    end

    test "inserts recipe with tags" do
      {:ok, recipe} = Recipes.create(recipe_attrs(%{tags: ["quick", "batch"]}))
      tag_names = Enum.map(recipe.tags, & &1.name)
      assert "quick" in tag_names
      assert "batch" in tag_names
    end

    test "upserts ingredients — no duplicate names" do
      {:ok, _} = Recipes.create(recipe_attrs(%{ingredients: [%{name: "garlic"}]}))

      {:ok, _} =
        Recipes.create(recipe_attrs(%{title: "Recipe 2", ingredients: [%{name: "garlic"}]}))

      assert Repo.aggregate(Scullion.Recipes.Ingredient, :count) == 1
    end

    test "inserts recipe with ingredients" do
      attrs = recipe_attrs(%{ingredients: [%{name: "onion", quantity: 2, unit: "pcs"}]})
      {:ok, recipe} = Recipes.create(attrs)
      assert length(recipe.recipe_ingredients) == 1
      ri = hd(recipe.recipe_ingredients)
      assert ri.ingredient.name == "onion"
    end

    test "returns error for missing title" do
      assert {:error, changeset} = Recipes.create(%{})
      assert %{title: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update/2" do
    test "updates fields" do
      {:ok, recipe} = Recipes.create(recipe_attrs())
      {:ok, updated} = Recipes.update(recipe, %{title: "Updated", prep_time_minutes: 15})
      assert updated.title == "Updated"
      assert updated.prep_time_minutes == 15
    end

    test "replaces tags" do
      {:ok, recipe} = Recipes.create(recipe_attrs(%{tags: ["quick"]}))
      {:ok, updated} = Recipes.update(recipe, %{tags: ["batch", "vegetarian"]})
      tag_names = Enum.map(updated.tags, & &1.name)
      assert "batch" in tag_names
      assert "vegetarian" in tag_names
      refute "quick" in tag_names
    end

    test "nil tags leaves existing tags unchanged" do
      {:ok, recipe} = Recipes.create(recipe_attrs(%{tags: ["quick"]}))
      {:ok, updated} = Recipes.update(recipe, %{title: "New title"})
      tag_names = Enum.map(updated.tags, & &1.name)
      assert "quick" in tag_names
    end
  end

  describe "update/2 with ingredients" do
    test "replaces all ingredients on update" do
      {:ok, recipe} = Recipes.create(%{
        title: "Soup",
        recipe_type: :meal,
        ingredients: [%{name: "Water", quantity: "1", unit: "L"}]
      })

      {:ok, updated} = Recipes.update(recipe, %{
        ingredients: [
          %{name: "Chicken", quantity: "500", unit: "g"},
          %{name: "Salt", quantity: "1", unit: "tsp"}
        ]
      })

      names = Enum.map(updated.recipe_ingredients, & &1.ingredient.name)
      assert length(updated.recipe_ingredients) == 2
      assert "Chicken" in names
      assert "Salt" in names
      refute "Water" in names
    end

    test "clears all ingredients when passed empty list" do
      {:ok, recipe} = Recipes.create(%{
        title: "Soup",
        recipe_type: :meal,
        ingredients: [%{name: "Water", quantity: "1", unit: "L"}]
      })

      {:ok, updated} = Recipes.update(recipe, %{ingredients: []})
      assert updated.recipe_ingredients == []
    end

    test "does not touch ingredients when key is absent" do
      {:ok, recipe} = Recipes.create(%{
        title: "Soup",
        recipe_type: :meal,
        ingredients: [%{name: "Water", quantity: "1", unit: "L"}]
      })

      {:ok, updated} = Recipes.update(recipe, %{title: "Updated Soup"})
      assert length(updated.recipe_ingredients) == 1
      assert hd(updated.recipe_ingredients).ingredient.name == "Water"
    end
  end

  describe "list/1" do
    setup do
      {:ok, r1} =
        Recipes.create(%{
          title: "Alpha",
          recipe_type: :meal,
          prep_time_minutes: 10,
          cook_time_minutes: 20,
          tags: ["quick"]
        })

      {:ok, r2} =
        Recipes.create(%{
          title: "Beta",
          recipe_type: :component,
          prep_time_minutes: 5,
          cook_time_minutes: 60,
          tags: ["batch"]
        })

      {:ok, r3} =
        Recipes.create(%{
          title: "Gamma",
          recipe_type: :assembly,
          prep_time_minutes: 5,
          cook_time_minutes: 10,
          tags: ["quick", "vegetarian"]
        })

      %{r1: r1, r2: r2, r3: r3}
    end

    test "returns all recipes by default" do
      assert length(Recipes.list()) == 3
    end

    test "filters by single tag" do
      results = Recipes.list(tags: ["quick"])
      titles = Enum.map(results, & &1.title)
      assert "Alpha" in titles
      assert "Gamma" in titles
      refute "Beta" in titles
    end

    test "filters by multiple tags (AND)" do
      results = Recipes.list(tags: ["quick", "vegetarian"])
      assert length(results) == 1
      assert hd(results).title == "Gamma"
    end

    test "filters by type" do
      results = Recipes.list(type: :component)
      assert length(results) == 1
      assert hd(results).title == "Beta"
    end

    test "filters by max_minutes" do
      results = Recipes.list(max_minutes: 30)
      titles = Enum.map(results, & &1.title)
      assert "Alpha" in titles
      assert "Gamma" in titles
      refute "Beta" in titles
    end

    test "weeknight_friendly: quick tag + ≤45 min" do
      results = Recipes.list(weeknight_friendly: true)
      titles = Enum.map(results, & &1.title)
      assert "Alpha" in titles
      assert "Gamma" in titles
      refute "Beta" in titles
    end

    test "sorts alphabetically" do
      results = Recipes.list(sort: :alphabetical)
      titles = Enum.map(results, & &1.title)
      assert titles == Enum.sort(titles)
    end
  end

  describe "search/1" do
    setup do
      {:ok, _} = Recipes.create(%{title: "Chicken Soup", recipe_type: :meal})

      {:ok, _} =
        Recipes.create(%{title: "Pasta", recipe_type: :meal, ingredients: [%{name: "garlic"}]})

      :ok
    end

    test "matches by title" do
      results = Recipes.search("chicken")
      assert length(results) == 1
      assert hd(results).title == "Chicken Soup"
    end

    test "matches by ingredient name" do
      results = Recipes.search("garlic")
      assert length(results) == 1
      assert hd(results).title == "Pasta"
    end

    test "returns empty list for no match" do
      assert [] = Recipes.search("xyz123notarecipe")
    end

    test "returns empty list for empty query" do
      assert [] = Recipes.search("")
    end
  end

  describe "record_used/1" do
    test "sets last_used_at" do
      {:ok, recipe} = Recipes.create(recipe_attrs())
      assert is_nil(recipe.last_used_at)
      :ok = Recipes.record_used(recipe.id)
      updated = Recipes.get!(recipe.id)
      refute is_nil(updated.last_used_at)
    end
  end

  describe "delete/1" do
    test "removes the recipe" do
      {:ok, recipe} = Recipes.create(recipe_attrs())
      {:ok, _} = Recipes.delete(recipe)
      assert_raise Ecto.NoResultsError, fn -> Recipes.get!(recipe.id) end
    end
  end
end
