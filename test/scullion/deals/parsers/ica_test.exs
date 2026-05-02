defmodule Scullion.Deals.Parsers.ICATest do
  use ExUnit.Case, async: true

  alias Scullion.Deals.Parsers.ICA

  @fixture_html """
  <div data-testid="offer-card">
    <span data-testid="product-name">Kycklingfilé</span>
    <span data-testid="brand">Kronfågel</span>
    <span data-testid="price">59,90/kg</span>
    <span data-testid="splash">Köp 2 betala för 1</span>
  </div>
  <div data-testid="offer-card">
    <span data-testid="product-name">Färsk pasta</span>
    <span data-testid="price">29,90/st</span>
  </div>
  """

  test "parse/1 extracts deals from offer cards" do
    assert {:ok, deals} = ICA.parse(@fixture_html)
    assert length(deals) == 2

    [chicken | _] = deals
    assert chicken.product_name == "Kycklingfilé"
    assert chicken.brand == "Kronfågel"
    assert chicken.store == "ica"
    assert chicken.source == :scraped
    assert %Decimal{} = chicken.price
    assert chicken.offer_condition == "Köp 2 betala för 1"
  end

  test "parse/1 extracts price unit from price text" do
    assert {:ok, [deal | _]} = ICA.parse(@fixture_html)
    assert deal.price_unit == "kr/kg"
  end

  test "parse/1 returns empty list for page with no offer cards" do
    assert {:ok, []} = ICA.parse("<html><body>No offers</body></html>")
  end

  test "parse/1 always returns :ok tuple" do
    assert {:ok, _} = ICA.parse("")
  end

  test "parse/1 skips cards with empty product names" do
    html = """
    <div data-testid="offer-card">
      <span data-testid="product-name"></span>
    </div>
    <div data-testid="offer-card">
      <span data-testid="product-name">Mjölk</span>
    </div>
    """

    assert {:ok, [deal]} = ICA.parse(html)
    assert deal.product_name == "Mjölk"
  end
end
