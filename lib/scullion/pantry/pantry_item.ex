defmodule Scullion.Pantry.PantryItem do
  use Ecto.Schema

  schema "pantry_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :category, :string
    field :ingredient_id, :integer
    field :added_at, :utc_datetime
    field :expires_at, :utc_datetime
    timestamps()
  end
end
