defmodule Tore.Repo.Migrations.AddLocaleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :locale, :string, default: "sv", null: false
    end
  end
end
