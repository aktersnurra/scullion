defmodule Tore.Accounts.DeviceToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "device_tokens" do
    field :token_hash, :string
    field :name, :string
    field :revoked_at, :utc_datetime
    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash])
    |> validate_required([:name, :token_hash])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:token_hash)
  end

  def revoke_changeset(token) do
    change(token, revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
