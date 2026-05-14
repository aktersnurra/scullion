defmodule Tore.Repo.Migrations.CreateIngredients do
  use Ecto.Migration

  def change do
    create table(:ingredients) do
      add :name, :string, null: false
      add :category, :string
      add :default_unit, :string
      timestamps()
    end

    create unique_index(:ingredients, [:name])
  end
end
