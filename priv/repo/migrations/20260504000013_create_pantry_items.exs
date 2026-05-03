defmodule Scullion.Repo.Migrations.CreatePantryItems do
  use Ecto.Migration

  def change do
    create table(:pantry_items) do
      add :name, :string, null: false
      add :quantity, :decimal
      add :unit, :string
      add :category, :string
      add :ingredient_id, references(:ingredients, on_delete: :nilify_all)
      add :added_at, :date, null: false
      add :expires_at, :date
      timestamps()
    end

    create index(:pantry_items, [:ingredient_id])
  end
end
