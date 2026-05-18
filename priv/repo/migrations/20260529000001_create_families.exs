defmodule Tore.Repo.Migrations.CreateFamilies do
  use Ecto.Migration

  def change do
    create table(:families) do
      add :name, :string, null: false
      add :locale, :string, null: false, default: "sv"
      timestamps()
    end
  end
end
