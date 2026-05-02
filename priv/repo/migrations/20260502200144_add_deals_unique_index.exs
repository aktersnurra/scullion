defmodule Scullion.Repo.Migrations.AddDealsUniqueIndex do
  use Ecto.Migration

  def change do
    create unique_index(:deals, [:store, :product_name])
  end
end
