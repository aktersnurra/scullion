defmodule Tore.Deals do
  alias Tore.{Repo, Deals.Deal, Deals.StoreConfig}
  import Ecto.Query

  @spec upsert_deals([map()]) :: {:ok, integer()} | {:error, term()}
  def upsert_deals(deals) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(deals, fn d ->
        d
        |> Map.put_new(:source, :scraped)
        |> Map.merge(%{inserted_at: now, updated_at: now})
      end)

    {count, _} =
      Repo.insert_all(Deal, rows,
        on_conflict: :nothing,
        conflict_target: [:store, :product_name]
      )

    {:ok, count}
  end

  @spec list_current() :: [Deal.t()]
  def list_current do
    today = Date.utc_today()
    Repo.all(from d in Deal, where: is_nil(d.valid_until) or d.valid_until >= ^today)
  end

  @spec clear_expired() :: :ok
  def clear_expired do
    today = Date.utc_today()
    Repo.delete_all(from d in Deal, where: not is_nil(d.valid_until) and d.valid_until < ^today)
    :ok
  end

  @spec list_store_configs() :: [StoreConfig.t()]
  def list_store_configs, do: Repo.all(StoreConfig)

  @spec create_store_config(map()) :: {:ok, StoreConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_store_config(attrs) do
    %StoreConfig{}
    |> StoreConfig.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_store_config(StoreConfig.t(), map()) :: {:ok, StoreConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_store_config(config, attrs) do
    config
    |> StoreConfig.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_store_config(StoreConfig.t()) :: {:ok, StoreConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_store_config(config), do: Repo.delete(config)

  @spec get_store_config!(integer()) :: StoreConfig.t()
  def get_store_config!(id), do: Repo.get!(StoreConfig, id)
end
