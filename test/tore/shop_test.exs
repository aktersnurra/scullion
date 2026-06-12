defmodule Tore.ShopTest do
  use ExUnit.Case, async: false

  import Mox

  alias Tore.{Shop, Recipes}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tore.Repo)
    Phoenix.PubSub.subscribe(Tore.PubSub, "shop_list")

    # Shop.add_item/build_list call the LLM to classify items and
    # filter the pantry; stub them so these tests don't depend on a real model.
    stub(Tore.MockLLM, :classify_grocery_item, fn _name -> {:ok, :other} end)
    stub(Tore.MockLLM, :filter_pantry_items, fn items, _pantry -> {:ok, items} end)

    :ok
  end

  defp list_id, do: "shop_list:2026-04-27"
  defp week_start, do: ~D[2026-04-27]

  test "load_list returns initial state for new list" do
    assert {:ok, state} = Shop.load_list(list_id())
    assert state.items == %{}
  end

  test "add_item persists ItemAdded with generated item_id" do
    assert {:ok, _events} = Shop.add_item(list_id(), "Milk", Decimal.new("1"), "l", 1)
    assert {:ok, state} = Shop.load_list(list_id())
    item = state.items |> Map.values() |> List.first()
    assert item.name == "Milk"
    assert item.unit == "l"
    assert item.checked == false
  end

  test "add_item broadcasts to shop_list topic" do
    Shop.add_item(list_id(), "Eggs", nil, nil, 1)
    assert_receive {:events, [%Tore.Shop.Events.ItemAdded{}]}
  end

  test "check_item persists ItemChecked and broadcasts" do
    Shop.add_item(list_id(), "Butter", nil, nil, 1)
    {:ok, state} = Shop.load_list(list_id())
    item_id = state.items |> Map.keys() |> List.first()

    assert {:ok, _} = Shop.check_item(list_id(), item_id, 1)
    {:ok, updated} = Shop.load_list(list_id())
    assert updated.items[item_id].checked == true

    assert_receive {:events, [%Tore.Shop.Events.ItemChecked{}]}
  end

  test "check_item returns error for unknown item_id" do
    assert {:error, :item_not_found} = Shop.check_item(list_id(), "no-such-id", 1)
  end

  test "check_item adds item to pantry" do
    Shop.add_item(list_id(), "Pasta", Decimal.new("500"), "g", 1)
    {:ok, state} = Shop.load_list(list_id())
    item_id = state.items |> Map.keys() |> List.first()

    Shop.check_item(list_id(), item_id, 1)
    pantry = Tore.Pantry.list_inventory()
    assert Enum.any?(pantry, &(&1.name == "pasta"))
  end

  test "build_list aggregates recipe ingredients and broadcasts" do
    {:ok, recipe} =
      Recipes.create(%{
        title: "Test Recipe",
        ingredients: [%{name: "onion", quantity: Decimal.new("2"), unit: "pcs"}]
      })

    assert {:ok, _} = Shop.build_list(list_id(), week_start(), [recipe.id])
    {:ok, state} = Shop.load_list(list_id())
    item = state.items |> Map.values() |> Enum.find(&(&1.name == "onion"))
    assert item
    assert_receive {:events, [%Tore.Shop.Events.ListBuilt{}]}
  end
end
