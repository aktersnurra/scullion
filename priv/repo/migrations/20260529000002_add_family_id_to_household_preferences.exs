defmodule Tore.Repo.Migrations.AddFamilyIdToHouseholdPreferences do
  use Ecto.Migration

  def change do
    alter table(:household_preferences) do
      add :family_id, references(:families, on_delete: :delete_all)
    end
  end
end
