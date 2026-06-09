defmodule Tore.Repo.Migrations.ReplaceCorrelationIdWithRunStreamId do
  use Ecto.Migration

  def up do
    # Pre-production: existing rows are not load-bearing.
    execute("DELETE FROM ai_operations")

    drop_if_exists unique_index(:ai_operations, [:correlation_id, :step_index],
                     name: :ai_operations_correlation_id_step_index_index
                   )

    alter table(:ai_operations) do
      add :run_stream_id, :string, null: false
      remove :correlation_id
    end

    create unique_index(:ai_operations, [:run_stream_id, :step_index],
             name: :ai_operations_run_stream_id_step_index_index
           )
  end

  def down do
    raise Ecto.MigrationError,
      message: "irreversible — restore from backup if you need correlation_id back"
  end
end
