defmodule Tore.Repo.Migrations.CreateStoreConfigs do
  use Ecto.Migration

  def change do
    create table(:store_configs) do
      add :name, :string, null: false
      add :chain, :string, null: false
      add :store_id, :string
      add :url, :string
      add :scrape_enabled, :boolean, default: false, null: false
      timestamps()
    end
  end
end
