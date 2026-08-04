defmodule Tore.Repo.Migrations.AddProposedRunToCounterNotes do
  use Ecto.Migration

  def change do
    alter table(:counter_notes) do
      add :proposed_run, :map
    end
  end
end
