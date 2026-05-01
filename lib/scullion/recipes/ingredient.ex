defmodule Scullion.Recipes.Ingredient do
  use Ecto.Schema

  schema "ingredients" do
    field :name, :string
    field :category, :string
    field :default_unit, :string
    timestamps()
  end
end
