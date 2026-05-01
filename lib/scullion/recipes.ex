defmodule Scullion.Recipes do
  @spec create(map()) :: {:ok, term()} | {:error, term()}
  def create(_attrs), do: {:error, :not_implemented}

  @spec update(term(), map()) :: {:ok, term()} | {:error, term()}
  def update(_recipe, _attrs), do: {:error, :not_implemented}

  @spec list() :: [term()]
  def list, do: []

  @spec search(String.t()) :: [term()]
  def search(_query), do: []

  @spec get(term()) :: {:ok, term()} | {:error, :not_found}
  def get(_id), do: {:error, :not_found}

  @spec scrape_from_url(String.t()) :: {:ok, map()} | {:error, term()}
  def scrape_from_url(_url), do: {:error, :not_implemented}
end
