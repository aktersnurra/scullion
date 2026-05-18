defmodule Tore.Family.FamilySchema do
  use Ecto.Schema
  import Ecto.Changeset

  schema "families" do
    field :name, :string
    field :locale, :string, default: "sv"
    has_many :users, Tore.Accounts.User, foreign_key: :family_id
    has_one :preferences, Tore.Household.Preferences, foreign_key: :family_id
    timestamps()
  end

  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name, :locale])
    |> validate_required([:name, :locale])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:locale, ~w(sv en))
  end
end
