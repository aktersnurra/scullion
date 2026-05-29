defmodule Tore.Repo.Migrations.AddFamilyIdToUsers do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO families (name, locale, inserted_at, updated_at)
    SELECT 'Home', 'sv', datetime('now'), datetime('now')
    WHERE NOT EXISTS (SELECT 1 FROM families)
    """

    alter table(:users) do
      add :family_id, references(:families, on_delete: :nilify_all)
    end

    execute """
    UPDATE users SET family_id = (SELECT id FROM families LIMIT 1)
    WHERE family_id IS NULL
    """
  end

  def down do
    alter table(:users) do
      remove :family_id
    end
  end
end
