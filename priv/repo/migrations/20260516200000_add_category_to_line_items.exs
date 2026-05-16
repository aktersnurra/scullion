defmodule Tore.Repo.Migrations.AddCategoryToLineItems do
  use Ecto.Migration

  def change do
    alter table(:line_items) do
      add :category, :string
    end
  end
end
