defmodule Scullion.Costs.DiningOut do
  use Ecto.Schema
  import Ecto.Changeset

  schema "dining_out" do
    field :date, :date
    field :description, :string
    field :total_amount, :decimal
    field :num_people, :integer, default: 1
    belongs_to :user, Scullion.Accounts.User
    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:date, :description, :total_amount, :num_people, :user_id])
    |> validate_required([:date, :total_amount, :user_id])
  end
end
