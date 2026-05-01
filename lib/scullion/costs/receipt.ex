defmodule Scullion.Costs.Receipt do
  use Ecto.Schema

  schema "receipts" do
    field :date, :date
    field :store_name, :string
    field :total_amount, :decimal
    field :image_path, :string
    field :user_id, :integer
    timestamps()
  end
end
