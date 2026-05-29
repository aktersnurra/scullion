defmodule Tore.Adapters.OpenRouterChatTest do
  use ExUnit.Case, async: false
  import Mox

  setup :verify_on_exit!

  test "chat/2 returns string reply via MockLLM" do
    Tore.MockLLM
    |> expect(:chat, fn system, messages ->
      assert is_binary(system)
      assert [%{"role" => "user", "content" => "What can I cook tonight?"}] = messages
      {:ok, "Try pasta!", %{prompt_tokens: 10, completion_tokens: 5, cost_usd: 0.0001}}
    end)

    assert {:ok, "Try pasta!", _usage} =
             Tore.MockLLM.chat("You are a cooking assistant.", [
               %{"role" => "user", "content" => "What can I cook tonight?"}
             ])
  end

  test "chat/2 propagates errors" do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages -> {:error, :rate_limited} end)

    assert {:error, :rate_limited} =
             Tore.MockLLM.chat("system", [%{"role" => "user", "content" => "hello"}])
  end
end
