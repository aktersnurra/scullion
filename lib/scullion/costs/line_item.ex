defmodule Scullion.Costs.LineItem do
  use Ecto.Schema

  schema "line_items" do
    field :receipt_id, :integer
    field :product_name, :string
    field :quantity, :decimal
    field :unit_price, :decimal
    field :total_price, :decimal
    timestamps()
  end
end
