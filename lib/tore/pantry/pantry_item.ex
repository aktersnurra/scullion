defmodule Tore.Pantry.PantryItem do
  use Ecto.Schema
  import Ecto.Changeset

  @categories [:dairy, :meat, :produce, :frozen, :dry_goods, :canned, :herbs_spices, :condiments, :other]

  def categories, do: @categories

  def category_values, do: Enum.map(@categories, &Atom.to_string/1)

  schema "pantry_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :category, :string
    field :added_at, :date
    field :expires_at, :date
    belongs_to :ingredient, Tore.Recipes.Ingredient
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :quantity, :unit, :category, :ingredient_id, :added_at, :expires_at])
    |> validate_required([:name, :added_at])
    |> update_change(:name, &normalize_name/1)
    |> validate_inclusion(:category, category_values())
  end

  defp normalize_name(name), do: name |> String.trim() |> String.downcase()
end
