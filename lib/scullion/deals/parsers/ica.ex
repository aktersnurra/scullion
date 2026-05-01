defmodule Scullion.Deals.Parsers.ICA do
  @behaviour Scullion.Deals.Parsers.Parser

  @impl Scullion.Deals.Parsers.Parser
  def parse(_html), do: {:error, :not_implemented}
end
