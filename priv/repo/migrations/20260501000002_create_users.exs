defmodule Scullion.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :account_code_hash, :string, null: false
      add :role, :string, null: false, default: "member"
      add :preferences, :map, null: false, default: %{}
      timestamps()
    end
  end
end
