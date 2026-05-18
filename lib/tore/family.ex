defmodule Tore.Family do
  import Ecto.Query
  alias Tore.{Repo, Family.FamilySchema}

  @spec get_family!() :: FamilySchema.t()
  def get_family! do
    case Repo.one(FamilySchema) do
      nil ->
        %FamilySchema{}
        |> FamilySchema.changeset(%{name: "Home", locale: "sv"})
        |> Repo.insert!()

      family ->
        family
    end
  end

  @spec create_family(map()) :: {:ok, FamilySchema.t()} | {:error, Ecto.Changeset.t()}
  def create_family(attrs) do
    %FamilySchema{}
    |> FamilySchema.changeset(attrs)
    |> Repo.insert()
  end
end
