defmodule Scullion.Repo.Migrations.CreateDiningOut do
  use Ecto.Migration

  def change do
    create table(:dining_out) do
      add :date, :date, null: false
      add :description, :string
      add :total_amount, :decimal, null: false
      add :num_people, :integer, default: 1, null: false
      add :user_id, references(:users, on_delete: :nothing), null: false
      timestamps()
    end

    create index(:dining_out, [:user_id])
    create index(:dining_out, [:date])
  end
end
