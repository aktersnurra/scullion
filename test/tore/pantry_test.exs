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

  test "add_item/1 accepts valid category" do
    assert {:ok, item} = Pantry.add_item(%{name: "Mjölk", category: "dairy"})
    assert item.category == "dairy"
  end

  test "add_item/1 rejects invalid category" do
    assert {:error, changeset} = Pantry.add_item(%{name: "Mjölk", category: "invalid"})
    assert changeset.errors[:category]
  end

  test "list_inventory_grouped/0 groups items by category in enum order" do
    Pantry.add_item(%{name: "Ost", category: "dairy"})
    Pantry.add_item(%{name: "Kycklingfilé", category: "meat"})
    Pantry.add_item(%{name: "Mjölk", category: "dairy"})

    groups = Pantry.list_inventory_grouped()
    keys = Enum.map(groups, &elem(&1, 0))

    assert hd(keys) == :dairy
    assert :meat in keys

    {_, dairy_items} = Enum.find(groups, fn {k, _} -> k == :dairy end)
    assert Enum.map(dairy_items, & &1.name) == ["mjölk", "ost"]
  end

  test "list_inventory_grouped/0 puts uncategorised items last under nil key" do
    Pantry.add_item(%{name: "Mystisk sak"})
    Pantry.add_item(%{name: "Ost", category: "dairy"})

    groups = Pantry.list_inventory_grouped()
    last_key = groups |> List.last() |> elem(0)
    assert last_key == nil
  end

  test "PantryItem.categories/0 returns ordered list of atoms" do
    cats = Tore.Pantry.PantryItem.categories()
    assert is_list(cats)
    assert Enum.all?(cats, &is_atom/1)
    assert :dairy in cats
    assert :meat in cats
    assert :other in cats
  end
end
