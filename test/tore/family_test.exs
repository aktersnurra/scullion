defmodule Tore.FamilyTest do
  use Tore.DataCase, async: true
  alias Tore.Family

  test "get_family!/0 creates default family when none exists" do
    family = Family.get_family!()
    assert family.name == "Home"
    assert family.locale == "sv"
  end

  test "get_family!/0 returns existing family on second call" do
    f1 = Family.get_family!()
    f2 = Family.get_family!()
    assert f1.id == f2.id
  end

  test "create_family/1 inserts a family" do
    assert {:ok, family} = Family.create_family(%{name: "Rydholm", locale: "sv"})
    assert family.name == "Rydholm"
  end

  test "create_family/1 rejects invalid locale" do
    assert {:error, cs} = Family.create_family(%{name: "Test", locale: "zz"})
    assert cs.errors[:locale]
  end

  describe "preferences" do
    test "get_preferences/0 returns empty preferences struct when none exist" do
      prefs = Family.get_preferences()
      assert prefs.default_portions == 4
      assert prefs.dietary_restrictions == []
    end

    test "update_preferences/1 persists and returns updated preferences" do
      assert {:ok, prefs} = Family.update_preferences(%{default_portions: 6, dietary_restrictions: ["vegan"]})
      assert prefs.default_portions == 6
      assert prefs.dietary_restrictions == ["vegan"]
    end

    test "update_preferences/1 is idempotent — second update replaces first" do
      {:ok, _} = Family.update_preferences(%{default_portions: 6})
      assert {:ok, prefs} = Family.update_preferences(%{default_portions: 2})
      assert prefs.default_portions == 2
    end

    test "prefs_to_dietary_guidance/1 returns nil for empty prefs" do
      prefs = Family.get_preferences()
      assert Family.prefs_to_dietary_guidance(prefs) == nil
    end

    test "prefs_to_dietary_guidance/1 formats dietary restrictions" do
      {:ok, prefs} = Family.update_preferences(%{dietary_restrictions: ["vegetarian"], allergies: ["nuts"]})
      guidance = Family.prefs_to_dietary_guidance(prefs)
      assert guidance =~ "Diet: vegetarian"
      assert guidance =~ "Allergies/hard avoids: nuts"
    end
  end
end
