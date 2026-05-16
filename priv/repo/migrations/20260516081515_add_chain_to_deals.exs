defmodule Tore.Repo.Migrations.AddChainToDeals do
  use Ecto.Migration

  def change do
    # Wipe stale rows that used chain name as store (e.g. store = "ica")
    execute "DELETE FROM deals WHERE store IN ('ica', 'coop')", ""

    alter table(:deals) do
      add :chain, :string, null: false, default: "ica"
    end

    drop_if_exists unique_index(:deals, [:store, :product_name])
    create unique_index(:deals, [:chain, :store, :product_name])
  end
end
