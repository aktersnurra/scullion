defmodule Tore.Repo.Migrations.CreateCounterNotes do
  use Ecto.Migration

  def change do
    create table(:counter_notes) do
      add :surface, :string, null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :commands, :text
      add :confidence, :string, null: false, default: "medium"
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create index(:counter_notes, [:surface, :status])
  end
end
