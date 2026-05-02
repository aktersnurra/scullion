defmodule Scullion.Deals.Deal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deals" do
    field :store, :string
    field :store_location, :string
    field :product_name, :string
    field :brand, :string
    field :size, :string
    field :price, :decimal
    field :price_unit, :string
    field :offer_condition, :string
    field :valid_from, :date
    field :valid_until, :date
    field :source, Ecto.Enum, values: [:scraped, :vision, :manual]
    timestamps()
  end

  def changeset(deal, attrs) do
    deal
    |> cast(attrs, [
      :store, :store_location, :product_name, :brand, :size,
      :price, :price_unit, :offer_condition, :valid_from, :valid_until, :source
    ])
    |> validate_required([:store, :product_name, :source])
  end
end
