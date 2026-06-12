defmodule Tore.DealsScrapeTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
  end

  @ica_html ~s({"weeklyOffers":[{"details":{"name":"Kycklingfilé","brand":"Kronfågel"},"parsedMechanics":{"value1":"1","value2":"59","value4":"/kg"},"stores":[{"storeMarketingName":"ICA Maxi","regularPrice":"89"}],"comparisonPrice":null,"validTo":null}],"compensationOffersStatus":"ok"})

  test "scrape_url fetches HTML, parses deals, and upserts" do
    Tore.MockHTTP
    |> expect(:fetch, fn _url -> {:ok, @ica_html} end)

    assert {:ok, 1} =
             Tore.Deals.scrape_url("https://ica.se/erbjudanden/test-123/", :ica)

    deals = Tore.Deals.list_current()
    assert Enum.any?(deals, &(&1.product_name == "Kycklingfilé"))
  end

  test "scrape_url returns error on HTTP failure" do
    Tore.MockHTTP
    |> expect(:fetch, fn _url -> {:error, :timeout} end)

    assert {:error, :timeout} = Tore.Deals.scrape_url("https://ica.se/", :ica)
  end

  test "scrape_all returns :ok with no enabled store configs" do
    assert :ok = Tore.Deals.scrape_all()
  end
end
