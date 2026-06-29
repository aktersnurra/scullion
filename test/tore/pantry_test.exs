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

  test "PantryItem.categories/0 returns ordered list of atoms" do
    cats = Tore.Pantry.PantryItem.categories()
    assert is_list(cats)
    assert Enum.all?(cats, &is_atom/1)
    assert :dairy in cats
    assert :meat in cats
    assert :other in cats
  end

  test "PantryItem.beliefs/0 returns the four belief values as strings" do
    assert Tore.Pantry.PantryItem.beliefs() == ~w[confirmed probable uncertain missing]
  end

  test "add_item/1 defaults belief to confirmed for manual provenance" do
    {:ok, item} = Pantry.add_item(%{name: "Salt"})
    assert item.provenance == "manual"
    assert item.belief == "confirmed"
  end

  test "add_item/1 accepts an explicit belief value" do
    {:ok, item} = Pantry.add_item(%{name: "Mjöl", belief: "probable"})
    assert item.belief == "probable"
  end

  test "add_item/1 rejects an invalid belief value" do
    assert {:error, changeset} = Pantry.add_item(%{name: "Sirap", belief: "maybe"})
    assert changeset.errors[:belief]
  end

  test "PantryItem.derive_belief/1 maps provenance to default belief" do
    assert Tore.Pantry.PantryItem.derive_belief("manual") == "confirmed"
    assert Tore.Pantry.PantryItem.derive_belief("vision") == "confirmed"
    assert Tore.Pantry.PantryItem.derive_belief("receipt") == "probable"
    assert Tore.Pantry.PantryItem.derive_belief("grocery_checkoff") == "probable"
    assert Tore.Pantry.PantryItem.derive_belief("belief") == "uncertain"
  end

  test "upsert_belief/1 bump refreshes belief from incoming provenance" do
    {:ok, _item, :added, nil} =
      Pantry.upsert_belief(%{
        catalogue_name: "Mjölk",
        quantity: Decimal.new(1),
        unit: "L",
        provenance: "belief"
      })

    {:ok, bumped, :bumped, _before} =
      Pantry.upsert_belief(%{
        catalogue_name: "Mjölk",
        quantity: Decimal.new(1),
        unit: "L",
        provenance: "receipt"
      })

    assert bumped.belief == "probable"
  end

  test "upsert_belief/1 bump never weakens a confirmed belief" do
    {:ok, _item, :added, nil} =
      Pantry.upsert_belief(%{
        catalogue_name: "Smör",
        quantity: Decimal.new(1),
        unit: "kg",
        provenance: "vision"
      })

    {:ok, bumped, :bumped, _before} =
      Pantry.upsert_belief(%{
        catalogue_name: "Smör",
        quantity: Decimal.new(1),
        unit: "kg",
        provenance: "belief"
      })

    assert bumped.belief == "confirmed"
  end

  test "PantryItem.effective_belief/2 decays confirmed → probable after 14 days" do
    now = ~U[2026-06-29 12:00:00Z]
    fresh = %Tore.Pantry.PantryItem{belief: "confirmed", last_seen_at: ~U[2026-06-20 12:00:00Z]}
    stale = %Tore.Pantry.PantryItem{belief: "confirmed", last_seen_at: ~U[2026-06-10 12:00:00Z]}

    assert Tore.Pantry.PantryItem.effective_belief(fresh, now) == :confirmed
    assert Tore.Pantry.PantryItem.effective_belief(stale, now) == :probable
  end

  test "PantryItem.effective_belief/2 decays probable → uncertain after 30 days" do
    now = ~U[2026-06-29 12:00:00Z]
    fresh = %Tore.Pantry.PantryItem{belief: "probable", last_seen_at: ~U[2026-06-10 12:00:00Z]}
    stale = %Tore.Pantry.PantryItem{belief: "probable", last_seen_at: ~U[2026-05-01 12:00:00Z]}

    assert Tore.Pantry.PantryItem.effective_belief(fresh, now) == :probable
    assert Tore.Pantry.PantryItem.effective_belief(stale, now) == :uncertain
  end

  test "PantryItem.effective_belief/2 leaves uncertain and missing untouched" do
    now = ~U[2026-06-29 12:00:00Z]
    ancient = ~U[2024-01-01 00:00:00Z]
    uncertain = %Tore.Pantry.PantryItem{belief: "uncertain", last_seen_at: ancient}
    missing = %Tore.Pantry.PantryItem{belief: "missing", last_seen_at: ancient}

    assert Tore.Pantry.PantryItem.effective_belief(uncertain, now) == :uncertain
    assert Tore.Pantry.PantryItem.effective_belief(missing, now) == :missing
  end

  test "PantryItem.effective_belief/2 with no last_seen_at returns stored belief" do
    item = %Tore.Pantry.PantryItem{belief: "confirmed", last_seen_at: nil}
    assert Tore.Pantry.PantryItem.effective_belief(item, ~U[2026-06-29 12:00:00Z]) == :confirmed
  end

  test "list_inventory_by_belief/0 groups by *effective* belief, not stored" do
    {:ok, item, _, _} =
      Pantry.upsert_belief(%{catalogue_name: "Old milk", provenance: "vision"})

    # Backdate last_seen_at into the probable window (>14 days, <30 days)
    # so the confirmed row should decay to probable at read time.
    backdated = DateTime.utc_now() |> DateTime.add(-20, :day) |> DateTime.truncate(:second)

    item
    |> Ecto.Changeset.change(last_seen_at: backdated)
    |> Tore.Repo.update!()

    groups = Pantry.list_inventory_by_belief()
    assert {:probable, [decayed]} = Enum.find(groups, fn {b, _} -> b == :probable end)
    assert decayed.name == "old milk"
  end

  test "list_inventory_by_belief/0 groups items by belief in confidence order" do
    {:ok, _, _, _} =
      Pantry.upsert_belief(%{catalogue_name: "Mjölk", provenance: "receipt"})

    {:ok, _, _, _} =
      Pantry.upsert_belief(%{catalogue_name: "Salt", provenance: "manual"})

    {:ok, _, _, _} =
      Pantry.upsert_belief(%{catalogue_name: "Mjöl", provenance: "belief"})

    groups = Pantry.list_inventory_by_belief()
    keys = Enum.map(groups, &elem(&1, 0))

    assert keys == [:confirmed, :probable, :uncertain]
  end
end
