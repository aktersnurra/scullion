defmodule Scullion.Costs.DiningOut do
  use Ecto.Schema

  schema "dining_out" do
    field :date, :date
    field :description, :string
    field :total_amount, :decimal
    field :num_people, :integer
    field :user_id, :integer
    timestamps()
  end
end
