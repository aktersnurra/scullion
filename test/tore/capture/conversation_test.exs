defmodule Tore.Capture.ConversationTest do
  use Tore.DataCase, async: false
  import Mox

  setup :verify_on_exit!

  test "reply/1 returns reply from LLM" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages, _opts ->
      {:ok, "Pasta sounds great!", %{prompt_tokens: 20, completion_tokens: 10, cost_usd: 0.0001}}
    end)

    assert {:ok, "Pasta sounds great!", nil} =
             Tore.Capture.Conversation.reply("What should I cook tonight?")
  end

  test "reply/1 logs to ai_operations" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages, _opts ->
      {:ok, "Soup!", %{prompt_tokens: 5, completion_tokens: 3, cost_usd: 0.00001}}
    end)

    Tore.Capture.Conversation.reply("Something warm?")

    ops = Tore.Repo.all(Tore.AiOperations.AiOperation)
    kinds = Enum.map(ops, & &1.kind)
    assert "chat" in kinds
    assert "chat_reply" in kinds
  end

  test "reply/1 propagates LLM errors" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages, _opts -> {:error, :rate_limited} end)

    assert {:error, :rate_limited} =
             Tore.Capture.Conversation.reply("hello")
  end

  test "the chat system prompt includes the role preamble and composed household context" do
    {:ok, _} = Tore.Household.update_preferences(%{dietary_restrictions: ["vegetarian"]})
    test_pid = self()

    Mox.expect(Tore.MockLLM, :chat, fn sys, _messages, _opts ->
      send(test_pid, {:system_prompt, sys})
      {:ok, "Hej!", %{}}
    end)

    {:ok, _reply, nil} = Tore.Capture.Conversation.reply("hello")

    assert_receive {:system_prompt, sys}
    assert sys =~ "Tore"
    assert sys =~ "Household preferences:"
  end

  test "the chat system prompt states today's date" do
    test_pid = self()

    Mox.expect(Tore.MockLLM, :chat, fn sys, _messages, _opts ->
      send(test_pid, {:system_prompt, sys})
      {:ok, "Hej!", %{}}
    end)

    {:ok, _reply, nil} = Tore.Capture.Conversation.reply("hello")

    assert_receive {:system_prompt, sys}
    expected = "Today is #{Calendar.strftime(Date.utc_today(), "%A, %B %-d, %Y")}."
    assert sys =~ expected
  end
end
