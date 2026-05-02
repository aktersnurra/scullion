defmodule Scullion.Deals.StoreConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "store_configs" do
    field :name, :string
    field :chain, Ecto.Enum, values: [:ica, :coop]
    field :store_id, :string
    field :url, :string
    field :scrape_enabled, :boolean, default: false
    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:name, :chain, :store_id, :url, :scrape_enabled])
    |> validate_required([:name, :chain])
  end
end
