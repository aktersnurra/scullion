defmodule Tore.Repo.Migrations.CreateAiOperations do
  use Ecto.Migration

  def change do
    create table(:ai_operations) do
      add :correlation_id, :string, null: false
      add :kind, :string, null: false
      add :payload, :text
      add :result, :text
      add :undo_op_id, :integer
      add :inserted_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP")
    end

    create unique_index(:ai_operations, [:correlation_id])
  end
end
