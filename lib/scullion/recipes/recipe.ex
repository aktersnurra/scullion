defmodule Scullion.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recipes" do
    field :title, :string
    field :description, :string
    field :instructions, :string
    field :recipe_type, Ecto.Enum, values: [:meal, :component, :assembly], default: :meal
    field :base_servings, :integer
    field :prep_time_minutes, :integer
    field :cook_time_minutes, :integer
    field :source_url, :string
    field :video_url, :string
    field :image_path, :string
    field :last_used_at, :utc_datetime
    field :created_by, :integer
    has_many :recipe_ingredients, Scullion.Recipes.RecipeIngredient
    many_to_many :tags, Scullion.Recipes.Tag, join_through: Scullion.Recipes.RecipeTag, on_replace: :delete
    timestamps()
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [
      :title, :description, :instructions, :recipe_type,
      :base_servings, :prep_time_minutes, :cook_time_minutes,
      :source_url, :video_url, :image_path, :last_used_at, :created_by
    ])
    |> validate_required([:title])
    |> validate_inclusion(:recipe_type, [:meal, :component, :assembly])
  end

  def tag_changeset(recipe, tags) do
    recipe
    |> change()
    |> put_assoc(:tags, tags)
  end
end
