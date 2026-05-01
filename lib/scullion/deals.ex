defmodule Scullion.Deals do
  @spec upsert_deals([map()]) :: {:ok, integer()} | {:error, term()}
  def upsert_deals(_deals), do: {:error, :not_implemented}

  @spec list_current() :: [term()]
  def list_current, do: []

  @spec clear_expired() :: :ok | {:error, term()}
  def clear_expired, do: {:error, :not_implemented}
end
