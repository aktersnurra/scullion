defmodule Tore.Recipes.RecipeTag do
  use Ecto.Schema

  @primary_key false
  schema "recipe_tags" do
    belongs_to :recipe, Tore.Recipes.Recipe
    belongs_to :tag, Tore.Recipes.Tag
  end
end
