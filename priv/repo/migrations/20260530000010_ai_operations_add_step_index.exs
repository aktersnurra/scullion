defmodule Tore.Repo.Migrations.AiOperationsAddStepIndex do
  use Ecto.Migration

  def change do
    alter table(:ai_operations) do
      add :step_index, :integer, null: false, default: 0
    end

    drop_if_exists unique_index(:ai_operations, [:correlation_id])
    create unique_index(:ai_operations, [:correlation_id, :step_index])
  end
end
