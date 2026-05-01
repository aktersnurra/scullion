defmodule Scullion.Recipes.RecipeIngredient do
  use Ecto.Schema

  schema "recipe_ingredients" do
    field :recipe_id, :integer
    field :ingredient_id, :integer
    field :quantity, :decimal
    field :unit, :string
    field :notes, :string
    timestamps()
  end
end
