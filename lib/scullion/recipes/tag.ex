defmodule Scullion.Recipes.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    many_to_many :recipes, Scullion.Recipes.Recipe, join_through: Scullion.Recipes.RecipeTag
    timestamps()
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
