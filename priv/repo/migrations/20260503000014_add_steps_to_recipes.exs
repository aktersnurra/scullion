defmodule Tore.Repo.Migrations.AddStepsToRecipes do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      add :steps, :text
    end
  end
end
