defmodule Tore.Repo.Migrations.RenameFamilyToHousehold do
  use Ecto.Migration

  def up do
    rename table(:families), to: table(:households)
    rename table(:family_insights), to: table(:household_insights)
    rename table(:users), :family_id, to: :household_id
    rename table(:household_preferences), :family_id, to: :household_id
  end

  def down do
    rename table(:household_preferences), :household_id, to: :family_id
    rename table(:users), :household_id, to: :family_id
    rename table(:household_insights), to: table(:family_insights)
    rename table(:households), to: table(:families)
  end
end
