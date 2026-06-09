defmodule Tore.CounterNotes.CounterNote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "counter_notes" do
    field :surface, :string
    field :kind, :string
    field :title, :string
    field :body, :string
    field :commands, :string
    field :confidence, :string, default: "medium"
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    timestamps(updated_at: false)
  end

  @valid_surfaces ~w(home week groceries pantry deals)
  @valid_kinds ~w(deal_opportunity plan_repair pantry_assumption habit_pattern)
  @valid_confidences ~w(low medium high)
  @valid_statuses ~w(pending accepted ignored expired)

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:surface, :kind, :title, :body, :commands, :confidence, :status, :expires_at])
    |> validate_required([:surface, :kind, :title, :body])
    |> validate_inclusion(:surface, @valid_surfaces)
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_inclusion(:confidence, @valid_confidences)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
