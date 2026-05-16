defmodule Tore.Deals do
  alias Tore.{Repo, Deals.Deal, Deals.StoreConfig}
  import Ecto.Query

  @spec upsert_deals([map()]) :: {:ok, integer()} | {:error, term()}
  def upsert_deals(deals) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      deals
      |> Enum.filter(
        &(not is_nil(&1[:store]) and not is_nil(&1[:product_name]) and not is_nil(&1[:chain]))
      )
      |> Enum.map(fn d ->
        d
        |> Map.put_new(:source, :scraped)
        |> Map.merge(%{inserted_at: now, updated_at: now})
      end)

    {count, _} =
      Repo.insert_all(Deal, rows,
        on_conflict: :nothing,
        conflict_target: [:chain, :store, :product_name]
      )

    {:ok, count}
  end

  @spec list_current() :: [Deal.t()]
  def list_current do
    today = Date.utc_today()
    Repo.all(from d in Deal, where: is_nil(d.valid_until) or d.valid_until >= ^today)
  end

  @spec rename_store(String.t(), String.t(), String.t()) :: :ok
  def rename_store(chain, old_store, new_store) do
    Repo.update_all(
      from(d in Deal, where: d.chain == ^chain and d.store == ^old_store),
      set: [store: new_store, store_location: new_store]
    )

    :ok
  end

  @spec clear_expired() :: :ok
  def clear_expired do
    today = Date.utc_today()
    week_start_dt = today |> Date.beginning_of_week() |> NaiveDateTime.new!(~T[00:00:00])

    Repo.delete_all(
      from d in Deal,
        where:
          (not is_nil(d.valid_until) and d.valid_until < ^today) or
            (is_nil(d.valid_until) and d.inserted_at < ^week_start_dt)
    )

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

  @spec update_store_config(StoreConfig.t(), map()) ::
          {:ok, StoreConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_store_config(config, attrs) do
    config
    |> StoreConfig.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_store_config(StoreConfig.t()) ::
          {:ok, StoreConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_store_config(config), do: Repo.delete(config)

  @spec get_store_config!(integer()) :: StoreConfig.t()
  def get_store_config!(id), do: Repo.get!(StoreConfig, id)
end
