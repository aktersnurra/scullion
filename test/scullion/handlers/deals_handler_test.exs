defmodule Scullion.Handlers.DealsHandlerTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Scullion.Repo)
  end

  @ica_html """
  <div data-testid="offer-card">
    <span data-testid="product-name">Kycklingfilé</span>
    <span data-testid="price">59,90/kg</span>
  </div>
  """

  test "scrape_url fetches HTML, parses deals, and upserts" do
    Scullion.MockHTTP
    |> expect(:fetch, fn _url -> {:ok, @ica_html} end)

    assert {:ok, 1} = Scullion.Handlers.DealsHandler.scrape_url("https://ica.se/erbjudanden/test-123/", :ica)

    deals = Scullion.Deals.list_current()
    assert Enum.any?(deals, &(&1.product_name == "Kycklingfilé"))
  end

  test "scrape_url returns error on HTTP failure" do
    Scullion.MockHTTP
    |> expect(:fetch, fn _url -> {:error, :timeout} end)

    assert {:error, :timeout} = Scullion.Handlers.DealsHandler.scrape_url("https://ica.se/", :ica)
  end

  test "scrape_all returns :ok with no enabled store configs" do
    assert :ok = Scullion.Handlers.DealsHandler.scrape_all()
  end
end
