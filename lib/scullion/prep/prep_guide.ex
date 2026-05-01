defmodule Scullion.Prep.PrepGuide do
  use Ecto.Schema

  schema "prep_guides" do
    field :week_start, :date
    field :instructions, :string
    field :timeline, {:array, :map}
    timestamps()
  end
end
