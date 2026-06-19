defmodule Tore.LLM.OpenAIChatWithToolsTest do
  use ExUnit.Case, async: false
  import Mox
  setup :verify_on_exit!

  alias Tore.LLM.OpenAI

  setup do
    prev = Application.get_env(:tore, :llm_adapter)
    Application.put_env(:tore, :llm_adapter, Tore.MockAdapter)
    on_exit(fn -> Application.put_env(:tore, :llm_adapter, prev) end)
    :ok
  end

  test "returns {:message, text} when the model emits no tool_calls" do
    expect(Tore.MockAdapter, :request, fn _body ->
      {:ok,
       %{
         "choices" => [%{"message" => %{"content" => "Done.", "tool_calls" => nil}}],
         "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 2, "total_tokens" => 7}
       }}
    end)

    assert {:ok, {:message, "Done."}, %{prompt_tokens: 5}} =
             OpenAI.chat_with_tools("sys", [%{role: "user", content: "hi"}], [], [])
  end

  test "returns {:tool_calls, list} when the model picks tools" do
    expect(Tore.MockAdapter, :request, fn _body ->
      {:ok,
       %{
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
       }}
    end)

    assert {:ok, {:tool_calls, [call]}, _usage} =
             OpenAI.chat_with_tools(
               "sys",
               [%{role: "user", content: "skip mon"}],
               [
                 %{
                   type: "function",
                   function: %{name: "skip_meal", description: "x", parameters: %{}}
                 }
               ],
               []
             )

    assert call.id == "call_1"
    assert call.name == "skip_meal"
    assert call.args == %{"slot_key" => "mon_dinner"}
  end
end
