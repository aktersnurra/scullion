defmodule Scullion.Deals.StoreConfig do
  use Ecto.Schema

  schema "store_configs" do
    field :name, :string
    field :chain, Ecto.Enum, values: [:ica, :coop]
    field :store_id, :string
    field :url, :string
    field :scrape_enabled, :boolean, default: false
    timestamps()
  end
end
