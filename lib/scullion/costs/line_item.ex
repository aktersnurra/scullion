defmodule Scullion.Costs.LineItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "line_items" do
    field :product_name, :string
    field :quantity, :decimal
    field :unit_price, :decimal
    field :total_price, :decimal
    belongs_to :receipt, Scullion.Costs.Receipt
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:product_name, :quantity, :unit_price, :total_price, :receipt_id])
    |> validate_required([:product_name, :receipt_id])
  end
end
