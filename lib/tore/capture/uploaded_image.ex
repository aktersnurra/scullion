defmodule Tore.Capture.UploadedImage do
  @moduledoc """
  Dedup record for an uploaded image. `content_hash` is the SHA-256 of the
  raw bytes, scoped per household. If the same household uploads the same
  bytes twice, the second upload is rejected and we point the user at the
  original `stream_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Tore.Household.HouseholdSchema

  @type t :: %__MODULE__{}

  schema "uploaded_images" do
    field :content_hash, :string
    field :stream_id, :string
    field :kind, :string

    belongs_to :household, HouseholdSchema

    timestamps(updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:content_hash, :stream_id, :kind, :household_id])
    |> validate_required([:content_hash, :stream_id, :kind, :household_id])
    |> unique_constraint([:household_id, :content_hash])
  end
end
