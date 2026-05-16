defmodule Tore.Pantry do
  import Ecto.Query
  alias Tore.Repo
  alias Tore.Pantry.PantryItem

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

  @spec list_inventory_grouped() :: [{atom() | nil, [PantryItem.t()]}]
  def list_inventory_grouped do
    items = Repo.all(from p in PantryItem, order_by: p.name)

    grouped = Enum.group_by(items, & &1.category)

    PantryItem.categories()
    |> Enum.flat_map(fn key ->
      str = Atom.to_string(key)

      case Map.get(grouped, str) do
        nil -> []
        bucket -> [{key, bucket}]
      end
    end)
    |> then(fn acc ->
      case Map.get(grouped, nil) do
        nil -> acc
        uncategorised -> acc ++ [{nil, uncategorised}]
      end
    end)
  end
end
