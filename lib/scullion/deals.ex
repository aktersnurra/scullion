defmodule Scullion.Deals do
  alias Scullion.{Repo, Deals.Deal}
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
end
