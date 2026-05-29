defmodule Tore.Chat.ChatHandlerTest do
  use Tore.DataCase, async: false
  import Mox

  setup :verify_on_exit!

  test "handle_text/1 returns reply from LLM" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages ->
      {:ok, "Pasta sounds great!", %{prompt_tokens: 20, completion_tokens: 10, cost_usd: 0.0001}}
    end)

    assert {:ok, "Pasta sounds great!", nil} =
             Tore.Chat.ChatHandler.handle_text("What should I cook tonight?")
  end

  test "handle_text/1 logs to ai_operations" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages ->
      {:ok, "Soup!", %{prompt_tokens: 5, completion_tokens: 3, cost_usd: 0.00001}}
    end)

    Tore.Chat.ChatHandler.handle_text("Something warm?")

    ops = Tore.Repo.all(Tore.AiOperations.AiOperation)
    kinds = Enum.map(ops, & &1.kind)
    assert "chat" in kinds
    assert "chat_reply" in kinds
  end

  test "handle_text/1 propagates LLM errors" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages -> {:error, :rate_limited} end)

    assert {:error, :rate_limited} =
             Tore.Chat.ChatHandler.handle_text("hello")
  end
end
