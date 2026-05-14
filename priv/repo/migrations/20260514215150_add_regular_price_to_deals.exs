defmodule Tore.Repo.Migrations.AddRegularPriceToDeals do
  use Ecto.Migration

  def change do
    alter table(:deals) do
      add :regular_price, :string
      add :comparison_price, :string
    end
  end
end
