defmodule Scullion.Deals.Deal do
  use Ecto.Schema

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
end
