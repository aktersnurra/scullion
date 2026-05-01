defmodule Scullion.Repo.Migrations.CreateDeviceTokens do
  use Ecto.Migration

  def change do
    create table(:device_tokens) do
      add :token_hash, :string, null: false
      add :name, :string, null: false
      add :revoked_at, :utc_datetime
      timestamps()
    end

    create unique_index(:device_tokens, [:token_hash])
  end
end
