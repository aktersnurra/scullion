defmodule Scullion.Recipes.ParserTest do
  use ExUnit.Case, async: true

  alias Scullion.Recipes.Parser

  test "parse_html/1 returns error for unimplemented parser" do
    assert {:error, :not_implemented} = Parser.parse_html("<html></html>")
  end
end
