defmodule Scullion.Adapters.ReqHTTP do
  @behaviour Scullion.HTTP

  @impl Scullion.HTTP
  def fetch(_url), do: {:error, :not_implemented}
end
