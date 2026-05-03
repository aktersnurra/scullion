defmodule Scullion.Pantry do
  import Ecto.Query
  alias Scullion.Repo
  alias Scullion.Pantry.PantryItem

  @spec add_item(map()) :: {:ok, PantryItem.t()} | {:error, Ecto.Changeset.t()}
  def add_item(attrs) do
    attrs = Map.put_new(attrs, :added_at, Date.utc_today())
    %PantryItem{} |> PantryItem.changeset(attrs) |> Repo.insert()
  end

  @spec remove_item(integer()) :: :ok | {:error, :not_found}
  def remove_item(item_id) do
    case Repo.get(PantryItem, item_id) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item) |> then(fn _ -> :ok end)
    end
  end

  @spec list_inventory() :: [PantryItem.t()]
  def list_inventory do
    Repo.all(from p in PantryItem, order_by: p.name)
  end
end
