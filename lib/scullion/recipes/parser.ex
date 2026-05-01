defmodule Scullion.Recipes.Parser do
  @spec parse_html(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_html(_html), do: {:error, :not_implemented}
end
