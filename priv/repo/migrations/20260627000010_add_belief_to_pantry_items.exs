defmodule Tore.Repo.Migrations.AddBeliefToPantryItems do
  use Ecto.Migration

  def up do
    alter table(:pantry_items) do
      add :belief, :string, default: "confirmed", null: false
    end

    execute("""
    UPDATE pantry_items SET belief = CASE provenance
      WHEN 'manual'           THEN 'confirmed'
      WHEN 'vision'           THEN 'confirmed'
      WHEN 'receipt'          THEN 'probable'
      WHEN 'grocery_checkoff' THEN 'probable'
      WHEN 'belief'           THEN 'uncertain'
      ELSE 'confirmed'
    END
    """)
  end

  def down do
    alter table(:pantry_items) do
      remove :belief
    end
  end
end
