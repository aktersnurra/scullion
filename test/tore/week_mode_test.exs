defmodule Tore.WeekModeTest do
  use Tore.DataCase, async: false
  alias Tore.WeekMode

  test "get_current_mode/0 returns 'normal' when nothing set" do
    assert WeekMode.get_current_mode() == "normal"
  end

  test "set_mode/1 and get_current_mode/0 round-trip" do
    {:ok, _} = WeekMode.set_mode("low_effort")
    assert WeekMode.get_current_mode() == "low_effort"
  end

  test "set_mode/1 twice overwrites — only one record per week" do
    {:ok, _} = WeekMode.set_mode("low_effort")
    {:ok, _} = WeekMode.set_mode("budget_week")
    assert WeekMode.get_current_mode() == "budget_week"
  end

  test "set_mode/1 with invalid mode returns error" do
    assert {:error, changeset} = WeekMode.set_mode("turbo_cook")
    assert changeset.errors[:mode]
  end

  test "mode_prompt_fragment/1 returns nil for normal" do
    assert WeekMode.mode_prompt_fragment("normal") == nil
  end

  test "mode_prompt_fragment/1 returns non-nil string for low_effort" do
    fragment = WeekMode.mode_prompt_fragment("low_effort")
    assert is_binary(fragment)
    assert String.contains?(fragment, "Low effort")
  end
end
