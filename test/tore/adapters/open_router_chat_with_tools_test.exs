defmodule Tore.Adapters.OpenRouterChatWithToolsTest do
  use ExUnit.Case, async: true
  import Mox
  setup :verify_on_exit!

  alias Tore.Adapters.OpenRouter

  setup do
    Application.put_env(:tore, :http_client, Tore.MockHTTP)
    Application.put_env(:tore, :openrouter_api_key, "test-key")
    :ok
  end

  test "returns {:message, text} when the model emits no tool_calls" do
    expect(Tore.MockHTTP, :post, fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [%{"message" => %{"content" => "Done.", "tool_calls" => nil}}],
           "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 2, "total_tokens" => 7}
         }}}
    end)

    assert {:ok, {:message, "Done."}, %{prompt_tokens: 5}} =
             OpenRouter.chat_with_tools("sys", [%{role: "user", content: "hi"}], [], [])
  end

  test "returns {:tool_calls, list} when the model picks tools" do
    expect(Tore.MockHTTP, :post, fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" => nil,
                 "tool_calls" => [
                   %{
                     "id" => "call_1",
                     "type" => "function",
                     "function" => %{
                       "name" => "skip_meal",
                       "arguments" => ~s({"slot_key":"mon_dinner"})
                     }
                   }
                 ]
               }
             }
           ],
           "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
         }}}
    end)

    assert {:ok, {:tool_calls, [call]}, _usage} =
             OpenRouter.chat_with_tools("sys", [%{role: "user", content: "skip mon"}], [
               %{type: "function", function: %{name: "skip_meal", description: "x", parameters: %{}}}
             ], [])

    assert call.id == "call_1"
    assert call.name == "skip_meal"
    assert call.args == %{"slot_key" => "mon_dinner"}
  end
end
