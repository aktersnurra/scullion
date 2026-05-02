defmodule Scullion.Recipes.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :name, :string
    field :category, :string
    field :default_unit, :string
    has_many :recipe_ingredients, Scullion.Recipes.RecipeIngredient
    timestamps()
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :category, :default_unit])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
