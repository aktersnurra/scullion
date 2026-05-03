defmodule Scullion.Handlers.GroceriesHandlerTest do
  use ExUnit.Case, async: false

  alias Scullion.{Handlers.GroceriesHandler, Recipes}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Scullion.Repo)
    Phoenix.PubSub.subscribe(Scullion.PubSub, "grocery_list")
    :ok
  end

  defp list_id, do: "grocery_list:2026-04-27"
  defp week_start, do: ~D[2026-04-27]

  test "load_list returns initial state for new list" do
    assert {:ok, state} = GroceriesHandler.load_list(list_id())
    assert state.items == %{}
  end

  test "add_item persists ItemAdded with generated item_id" do
    assert {:ok, _events} = GroceriesHandler.add_item(list_id(), "Milk", Decimal.new("1"), "l", 1)
    assert {:ok, state} = GroceriesHandler.load_list(list_id())
    item = state.items |> Map.values() |> List.first()
    assert item.name == "Milk"
    assert item.unit == "l"
    assert item.checked == false
  end

  test "add_item broadcasts to grocery_list topic" do
    GroceriesHandler.add_item(list_id(), "Eggs", nil, nil, 1)
    assert_receive {:events, [%Scullion.Groceries.Events.ItemAdded{}]}
  end

  test "check_item persists ItemChecked and broadcasts" do
    GroceriesHandler.add_item(list_id(), "Butter", nil, nil, 1)
    {:ok, state} = GroceriesHandler.load_list(list_id())
    item_id = state.items |> Map.keys() |> List.first()

    assert {:ok, _} = GroceriesHandler.check_item(list_id(), item_id, 1)
    {:ok, updated} = GroceriesHandler.load_list(list_id())
    assert updated.items[item_id].checked == true

    assert_receive {:events, [%Scullion.Groceries.Events.ItemChecked{}]}
  end

  test "check_item returns error for unknown item_id" do
    assert {:error, :item_not_found} = GroceriesHandler.check_item(list_id(), "no-such-id", 1)
  end

  test "check_item adds item to pantry" do
    GroceriesHandler.add_item(list_id(), "Pasta", Decimal.new("500"), "g", 1)
    {:ok, state} = GroceriesHandler.load_list(list_id())
    item_id = state.items |> Map.keys() |> List.first()

    GroceriesHandler.check_item(list_id(), item_id, 1)
    pantry = Scullion.Pantry.list_inventory()
    assert Enum.any?(pantry, &(&1.name == "Pasta"))
  end

  test "build_list aggregates recipe ingredients and broadcasts" do
    {:ok, recipe} =
      Recipes.create(%{
        title: "Test Recipe",
        ingredients: [%{name: "onion", quantity: Decimal.new("2"), unit: "pcs"}]
      })

    assert {:ok, _} = GroceriesHandler.build_list(list_id(), week_start(), [recipe.id])
    {:ok, state} = GroceriesHandler.load_list(list_id())
    item = state.items |> Map.values() |> Enum.find(&(&1.name == "onion"))
    assert item
    assert_receive {:events, [%Scullion.Groceries.Events.ListBuilt{}]}
  end
end
