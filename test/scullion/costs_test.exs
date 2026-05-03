defmodule Scullion.CostsTest do
  use Scullion.DataCase, async: false

  alias Scullion.{Costs, Accounts}

  setup do
    {:ok, {user, _code}} = Accounts.create_user(%{name: "Tester"})
    %{user_id: user.id}
  end

  test "log_receipt/1 inserts receipt and returns it", %{user_id: user_id} do
    attrs = %{date: Date.utc_today(), store_name: "ICA", total_amount: Decimal.new("150.00"), user_id: user_id}
    assert {:ok, receipt} = Costs.log_receipt(attrs)
    assert receipt.store_name == "ICA"
  end

  test "log_receipt/1 inserts line items", %{user_id: user_id} do
    line_items = [%{product_name: "Mjölk", quantity: Decimal.new(2), unit_price: Decimal.new("10.00"), total_price: Decimal.new("20.00")}]
    attrs = %{date: Date.utc_today(), user_id: user_id, total_amount: Decimal.new("20.00"), line_items: line_items}
    assert {:ok, receipt} = Costs.log_receipt(attrs)
    loaded = Scullion.Repo.preload(receipt, :line_items)
    assert length(loaded.line_items) == 1
    assert hd(loaded.line_items).product_name == "Mjölk"
  end

  test "log_receipt/1 returns error on missing required fields" do
    assert {:error, _} = Costs.log_receipt(%{store_name: "ICA"})
  end

  test "log_dining_out/1 inserts entry", %{user_id: user_id} do
    attrs = %{date: Date.utc_today(), description: "Pizza Hut", total_amount: Decimal.new("300.00"), num_people: 2, user_id: user_id}
    assert {:ok, entry} = Costs.log_dining_out(attrs)
    assert entry.description == "Pizza Hut"
    assert entry.num_people == 2
  end

  test "weekly_summary/1 sums groceries and dining", %{user_id: user_id} do
    week_start = Date.beginning_of_week(Date.utc_today())
    Costs.log_receipt(%{date: week_start, total_amount: Decimal.new("200.00"), user_id: user_id})
    Costs.log_dining_out(%{date: week_start, total_amount: Decimal.new("100.00"), user_id: user_id})

    assert {:ok, summary} = Costs.weekly_summary(week_start)
    assert Decimal.equal?(summary.grocery_total, Decimal.new("200.00"))
    assert Decimal.equal?(summary.dining_total, Decimal.new("100.00"))
    assert Decimal.equal?(summary.total, Decimal.new("300.00"))
  end

  test "weekly_summary/1 returns zeros for empty week" do
    week_start = ~D[2020-01-06]
    assert {:ok, summary} = Costs.weekly_summary(week_start)
    assert Decimal.equal?(summary.grocery_total, Decimal.new(0))
    assert Decimal.equal?(summary.dining_total, Decimal.new(0))
  end

  test "monthly_summary/2 aggregates receipts and dining", %{user_id: user_id} do
    Costs.log_receipt(%{date: ~D[2026-05-01], total_amount: Decimal.new("500.00"), user_id: user_id})
    Costs.log_dining_out(%{date: ~D[2026-05-15], total_amount: Decimal.new("200.00"), user_id: user_id})

    assert {:ok, summary} = Costs.monthly_summary(2026, 5)
    assert Decimal.equal?(summary.grocery_total, Decimal.new("500.00"))
    assert Decimal.equal?(summary.dining_total, Decimal.new("200.00"))
    assert summary.receipt_count == 1
    assert summary.dining_count == 1
  end

  test "cost_per_meal/1 divides grocery total by meal count", %{user_id: user_id} do
    week_start = Date.beginning_of_week(Date.utc_today())
    Costs.log_receipt(%{date: week_start, total_amount: Decimal.new("700.00"), user_id: user_id})

    assert {:ok, per_meal} = Costs.cost_per_meal(%{week_start: week_start, meal_count: 7})
    assert Decimal.equal?(per_meal, Decimal.new("100.00"))
  end

  test "cost_per_meal/1 returns error for zero meal count" do
    assert {:error, :invalid_period} = Costs.cost_per_meal(%{week_start: Date.utc_today(), meal_count: 0})
  end
end
