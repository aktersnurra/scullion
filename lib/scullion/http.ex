defmodule Scullion.HTTP do
  @callback fetch(url :: String.t()) :: {:ok, binary()} | {:error, term()}
end
