defmodule Tore.Repo.Migrations.AddProvenanceLastSeenToPantryItems do
  use Ecto.Migration

  def change do
    alter table(:pantry_items) do
      add :provenance, :string, null: false, default: "manual"
      add :last_seen_at, :utc_datetime
    end

    # Backfill last_seen_at from added_at for existing rows so the
    # monotonicity invariant the PantryVerifier checks is satisfied from day
    # one.
    execute(
      "UPDATE pantry_items SET last_seen_at = datetime(added_at) WHERE last_seen_at IS NULL",
      ""
    )
  end
end
