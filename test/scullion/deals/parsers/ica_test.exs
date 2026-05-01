defmodule Scullion.Deals.Parsers.ICATest do
  use ExUnit.Case, async: true

  alias Scullion.Deals.Parsers.ICA

  test "parse/1 returns error for unimplemented parser" do
    assert {:error, :not_implemented} = ICA.parse("<html></html>")
  end
end
