defmodule Tore.Deals.Parsers.Parser do
  @callback parse(html :: String.t()) :: {:ok, [map()]} | {:error, term()}
end
