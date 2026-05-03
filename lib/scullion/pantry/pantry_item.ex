defmodule Scullion.Pantry.PantryItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pantry_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :category, :string
    field :added_at, :date
    field :expires_at, :date
    belongs_to :ingredient, Scullion.Recipes.Ingredient
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :quantity, :unit, :category, :ingredient_id, :added_at, :expires_at])
    |> validate_required([:name, :added_at])
  end
end
