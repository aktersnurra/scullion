defmodule Tore.Handlers.CostsHandlerTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
    {:ok, {user, _code}} = Tore.Accounts.create_user(%{name: "Tester"})
    %{user_id: user.id}
  end

  test "parse_and_log_receipt/2 calls LLM and persists receipt", %{user_id: user_id} do
    line_items = [%{product_name: "Bröd", quantity: Decimal.new(1), unit_price: Decimal.new("25.00"), total_price: Decimal.new("25.00")}]

    Tore.MockLLM
    |> expect(:parse_receipt_image, fn _binary -> {:ok, line_items, %{}} end)

    assert {:ok, receipt} = Tore.Handlers.CostsHandler.parse_and_log_receipt(<<1, 2, 3>>, user_id)
    assert receipt.user_id == user_id
    assert Decimal.equal?(receipt.total_amount, Decimal.new("25.00"))
  end

  test "parse_and_log_receipt/2 returns error when LLM fails", %{user_id: user_id} do
    Tore.MockLLM
    |> expect(:parse_receipt_image, fn _binary -> {:error, :rate_limited} end)

    assert {:error, :rate_limited} = Tore.Handlers.CostsHandler.parse_and_log_receipt(<<1>>, user_id)
  end

  test "log_dining_out/2 delegates to Costs context", %{user_id: user_id} do
    attrs = %{date: Date.utc_today(), description: "Sushi", total_amount: Decimal.new("400.00"), num_people: 2}
    assert {:ok, entry} = Tore.Handlers.CostsHandler.log_dining_out(attrs, user_id)
    assert entry.description == "Sushi"
  end
end
