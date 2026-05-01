defmodule Scullion.Recipes.Recipe do
  use Ecto.Schema

  schema "recipes" do
    field :title, :string
    field :description, :string
    field :instructions, :string
    field :base_servings, :integer
    field :prep_time_minutes, :integer
    field :cook_time_minutes, :integer
    field :source_url, :string
    field :video_url, :string
    field :last_used_at, :utc_datetime
    field :created_by, :integer
    timestamps()
  end
end
