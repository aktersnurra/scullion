defmodule Scullion.Costs.Receipt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "receipts" do
    field :date, :date
    field :store_name, :string
    field :total_amount, :decimal
    field :image_path, :string
    belongs_to :user, Scullion.Accounts.User
    has_many :line_items, Scullion.Costs.LineItem
    timestamps()
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:date, :store_name, :total_amount, :image_path, :user_id])
    |> validate_required([:date, :user_id])
  end
end
