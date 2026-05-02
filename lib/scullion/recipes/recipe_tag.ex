defmodule Scullion.Recipes.RecipeTag do
  use Ecto.Schema

  @primary_key false
  schema "recipe_tags" do
    belongs_to :recipe, Scullion.Recipes.Recipe
    belongs_to :tag, Scullion.Recipes.Tag
  end
end
