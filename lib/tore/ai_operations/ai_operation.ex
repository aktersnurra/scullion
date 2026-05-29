defmodule Tore.AiOperations.AiOperation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_operations" do
    field :correlation_id, :string
    field :kind, :string
    field :payload, :string
    field :result, :string
    field :undo_op_id, :integer
    field :inserted_at, :utc_datetime, autogenerate: false
  end

  def changeset(op, attrs) do
    op
    |> cast(attrs, [:correlation_id, :kind, :payload, :result, :undo_op_id])
    |> validate_required([:correlation_id, :kind])
    |> unique_constraint(:correlation_id)
    |> put_inserted_at()
  end

  defp put_inserted_at(changeset) do
    if get_field(changeset, :inserted_at) do
      changeset
    else
      put_change(changeset, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end
end
