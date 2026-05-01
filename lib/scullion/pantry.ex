defmodule Scullion.Pantry do
  @spec add_item(map()) :: {:ok, term()} | {:error, term()}
  def add_item(_attrs), do: {:error, :not_implemented}

  @spec remove_item(term()) :: :ok | {:error, term()}
  def remove_item(_item_id), do: {:error, :not_implemented}

  @spec list_inventory() :: [term()]
  def list_inventory, do: []
end
