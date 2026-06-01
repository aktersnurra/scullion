defmodule Tore.HouseholdTest do
  use Tore.DataCase, async: true
  alias Tore.Household

  test "get_household!/0 creates default household when none exists" do
    household = Household.get_household!()
    assert household.name == "Home"
    assert household.locale == "sv"
  end

  test "get_household!/0 returns existing household on second call" do
    h1 = Household.get_household!()
    h2 = Household.get_household!()
    assert h1.id == h2.id
  end

  test "create_household/1 inserts a household" do
    assert {:ok, household} = Household.create_household(%{name: "Rydholm", locale: "sv"})
    assert household.name == "Rydholm"
  end

  test "create_household/1 rejects invalid locale" do
    assert {:error, cs} = Household.create_household(%{name: "Test", locale: "zz"})
    assert cs.errors[:locale]
  end

  describe "preferences" do
    test "get_preferences/0 returns empty preferences struct when none exist" do
      prefs = Household.get_preferences()
      assert prefs.default_portions == 4
      assert prefs.dietary_restrictions == []
    end

    test "update_preferences/1 persists and returns updated preferences" do
      assert {:ok, prefs} = Household.update_preferences(%{default_portions: 6, dietary_restrictions: ["vegan"]})
      assert prefs.default_portions == 6
      assert prefs.dietary_restrictions == ["vegan"]
    end

    test "update_preferences/1 is idempotent — second update replaces first" do
      {:ok, _} = Household.update_preferences(%{default_portions: 6})
      assert {:ok, prefs} = Household.update_preferences(%{default_portions: 2})
      assert prefs.default_portions == 2
    end

    test "prefs_to_dietary_guidance/1 returns nil for empty prefs" do
      prefs = Household.get_preferences()
      assert Household.prefs_to_dietary_guidance(prefs) == nil
    end

    test "prefs_to_dietary_guidance/1 formats dietary restrictions" do
      {:ok, prefs} = Household.update_preferences(%{dietary_restrictions: ["vegetarian"], allergies: ["nuts"]})
      guidance = Household.prefs_to_dietary_guidance(prefs)
      assert guidance =~ "Diet: vegetarian"
      assert guidance =~ "Allergies/hard avoids: nuts"
    end
  end
end
