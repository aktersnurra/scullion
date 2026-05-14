defmodule Tore.DealsTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
  end

  test "upsert_deals inserts new deals and returns count" do
    deals = [%{store: "ica", product_name: "Mjölk", source: :scraped}]
    assert {:ok, 1} = Tore.Deals.upsert_deals(deals)
  end

  test "upsert_deals inserts multiple deals" do
    deals = [
      %{store: "ica", product_name: "Bröd", source: :scraped},
      %{store: "ica", product_name: "Smör", source: :scraped}
    ]

    assert {:ok, 2} = Tore.Deals.upsert_deals(deals)
  end

  test "upsert_deals is idempotent via on_conflict: :nothing" do
    deals = [%{store: "ica", product_name: "Ost", source: :scraped}]
    assert {:ok, 1} = Tore.Deals.upsert_deals(deals)
    assert {:ok, 0} = Tore.Deals.upsert_deals(deals)
  end

  test "list_current returns deals without valid_until" do
    Tore.Deals.upsert_deals([%{store: "ica", product_name: "Bröd", source: :scraped}])
    deals = Tore.Deals.list_current()
    assert Enum.any?(deals, &(&1.product_name == "Bröd"))
  end

  test "list_current returns deals with future valid_until" do
    future = Date.add(Date.utc_today(), 7)

    Tore.Deals.upsert_deals([
      %{store: "ica", product_name: "Fisk", source: :scraped, valid_until: future}
    ])

    deals = Tore.Deals.list_current()
    assert Enum.any?(deals, &(&1.product_name == "Fisk"))
  end

  test "list_current excludes expired deals" do
    Tore.Deals.upsert_deals([
      %{store: "ica", product_name: "Expired", source: :scraped, valid_until: ~D[2020-01-01]}
    ])

    deals = Tore.Deals.list_current()
    refute Enum.any?(deals, &(&1.product_name == "Expired"))
  end

  test "clear_expired removes deals past valid_until" do
    Tore.Deals.upsert_deals([
      %{store: "ica", product_name: "OldDeal", source: :scraped, valid_until: ~D[2020-01-01]}
    ])

    Tore.Deals.clear_expired()
    deals = Tore.Deals.list_current()
    refute Enum.any?(deals, &(&1.product_name == "OldDeal"))
  end

  test "clear_expired keeps current deals" do
    Tore.Deals.upsert_deals([
      %{store: "ica", product_name: "Current", source: :scraped}
    ])

    Tore.Deals.clear_expired()
    deals = Tore.Deals.list_current()
    assert Enum.any?(deals, &(&1.product_name == "Current"))
  end
end
