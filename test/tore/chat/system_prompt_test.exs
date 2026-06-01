defmodule Tore.Chat.SystemPromptTest do
  use Tore.DataCase, async: false

  test "build/0 returns a non-empty string" do
    result = Tore.Chat.SystemPrompt.build()
    assert is_binary(result)
    assert byte_size(result) > 0
  end

  test "build/0 contains today's year" do
    today = Date.utc_today()
    result = Tore.Chat.SystemPrompt.build()
    assert result =~ Integer.to_string(today.year)
  end

  test "build/0 contains the assistant name" do
    result = Tore.Chat.SystemPrompt.build()
    assert result =~ "Tore"
  end

  test "build/0 includes insights when active insights exist" do
    {:ok, _} = Tore.Household.replace_insights([
      %{kind: "skip_pattern", body: "Mondays are often skipped.", confidence: 0.8, evidence: []}
    ])

    result = Tore.Chat.SystemPrompt.build()
    assert result =~ "Mondays are often skipped."
  end
end
