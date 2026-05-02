defmodule Scullion.Repo.Migrations.CreateDeals do
  use Ecto.Migration

  def change do
    create table(:deals) do
      add :store, :string, null: false
      add :store_location, :string
      add :product_name, :string, null: false
      add :brand, :string
      add :size, :string
      add :price, :decimal
      add :price_unit, :string
      add :offer_condition, :string
      add :valid_from, :date
      add :valid_until, :date
      add :source, :string, null: false, default: "scraped"
      timestamps()
    end

    create index(:deals, [:store, :valid_until])
  end
end
