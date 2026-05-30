defmodule Tore.HTTP do
  @callback fetch(url :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback post(url :: String.t(), opts :: keyword()) ::
              {:ok, %{status: integer(), body: term()} | Req.Response.t()}
              | {:error, term()}
end
