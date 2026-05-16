defmodule Tore.PantryTest do
  use Tore.DataCase, async: false

  alias Tore.Pantry

  test "add_item/1 inserts and returns pantry item" do
    assert {:ok, item} = Pantry.add_item(%{name: "Mjölk", quantity: Decimal.new(2), unit: "L"})
    assert item.name == "mjölk"
    assert item.added_at == Date.utc_today()
  end

  test "add_item/1 defaults added_at to today when omitted" do
    assert {:ok, item} = Pantry.add_item(%{name: "Smör"})
    assert item.added_at == Date.utc_today()
  end

  test "add_item/1 returns error on missing name" do
    assert {:error, changeset} = Pantry.add_item(%{quantity: Decimal.new(1)})
    assert changeset.errors[:name]
  end

  test "remove_item/1 deletes existing item and returns :ok" do
    {:ok, item} = Pantry.add_item(%{name: "Ägg"})
    assert :ok = Pantry.remove_item(item.id)
    assert Pantry.list_inventory() == []
  end

  test "remove_item/1 returns error for unknown id" do
    assert {:error, :not_found} = Pantry.remove_item(999_999)
  end

  test "list_inventory/0 returns all items ordered by name" do
    Pantry.add_item(%{name: "Ost"})
    Pantry.add_item(%{name: "Bröd"})
    names = Pantry.list_inventory() |> Enum.map(& &1.name)
    assert names == ["bröd", "ost"]
  end
end
