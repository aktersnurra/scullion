defmodule Tore.Recipes.RecipeIngredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recipe_ingredients" do
    belongs_to :recipe, Tore.Recipes.Recipe
    belongs_to :ingredient, Tore.Recipes.Ingredient
    field :quantity, :decimal
    field :unit, :string
    field :notes, :string
    timestamps()
  end

  def changeset(ri, attrs) do
    ri
    |> cast(attrs, [:recipe_id, :ingredient_id, :quantity, :unit, :notes])
    |> validate_required([:recipe_id, :ingredient_id])
  end
end
