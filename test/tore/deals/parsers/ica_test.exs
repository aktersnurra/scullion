defmodule Tore.Deals.Parsers.ICATest do
  use ExUnit.Case, async: true

  alias Tore.Deals.Parsers.ICA

  defp wrap_offers(offers_json) do
    ~s({"weeklyOffers":#{offers_json},"compensationOffersStatus":"ok"})
  end

  defp fixture_html do
    chicken =
      Jason.encode!(%{
        "details" => %{
          "name" => "Kycklingfilé",
          "brand" => "Kronfågel",
          "packageInformation" => "500g"
        },
        "parsedMechanics" => %{"value1" => "2", "value2" => "59", "value4" => "/kg"},
        "stores" => [%{"storeMarketingName" => "ICA Maxi", "regularPrice" => "89"}],
        "comparisonPrice" => "59:90/kg",
        "validTo" => "2026-05-18T00:00:00"
      })

    pasta =
      Jason.encode!(%{
        "details" => %{"name" => "Färsk pasta", "brand" => nil},
        "parsedMechanics" => %{"value1" => "1", "value2" => "29", "value4" => "/st"},
        "stores" => [%{"storeMarketingName" => "ICA Maxi", "regularPrice" => "35"}],
        "comparisonPrice" => nil,
        "validTo" => nil
      })

    wrap_offers("[#{chicken},#{pasta}]")
  end

  test "parse/1 extracts deals from offer cards" do
    assert {:ok, deals} = ICA.parse(fixture_html())
    assert length(deals) == 2

    [chicken | _] = deals
    assert chicken.product_name == "Kycklingfilé"
    assert chicken.brand == "Kronfågel"
    assert chicken.store == "ICA Maxi"
    assert chicken.source == :scraped
    assert %Decimal{} = chicken.price
  end

  test "parse/1 extracts price unit" do
    assert {:ok, [deal | _]} = ICA.parse(fixture_html())
    assert deal.price_unit == "/kg"
  end

  test "parse/1 returns error when no embedded data present" do
    assert {:error, :no_initial_data} = ICA.parse("<html><body>No offers</body></html>")
  end

  test "parse/1 parses valid_until date" do
    assert {:ok, [deal | _]} = ICA.parse(fixture_html())
    assert deal.valid_until == ~D[2026-05-18]
  end

  test "parse/1 normalises comparison price colon separator" do
    assert {:ok, [deal | _]} = ICA.parse(fixture_html())
    assert deal.comparison_price == "59.90/kg"
  end
end
