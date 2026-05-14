defmodule Tore.Deals.Parsers.Coop do
  @behaviour Tore.Deals.Parsers.Parser

  @impl Tore.Deals.Parsers.Parser
  def parse(_html), do: {:error, :not_implemented}
end
