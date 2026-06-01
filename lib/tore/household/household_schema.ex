defmodule Tore.Household.HouseholdSchema do
  use Ecto.Schema
  import Ecto.Changeset

  schema "households" do
    field :name, :string
    field :locale, :string, default: "sv"
    has_many :users, Tore.Accounts.User, foreign_key: :household_id
    has_one :preferences, Tore.Household.Preferences, foreign_key: :household_id
    timestamps()
  end

  def changeset(household, attrs) do
    household
    |> cast(attrs, [:name, :locale])
    |> validate_required([:name, :locale])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:locale, ~w(sv en))
  end
end
