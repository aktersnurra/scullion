defmodule Tore.Chat.ChatHandler do
  alias Tore.{AiOperations, Chat.SystemPrompt}

  @llm Application.compile_env(:tore, :llm_client)

  @spec handle_text(String.t(), keyword()) :: {:ok, String.t(), nil} | {:error, term()}
  def handle_text(text, _opts \\ []) do
    system = SystemPrompt.build()
    messages = [%{"role" => "user", "content" => text}]
    correlation_id = generate_correlation_id()

    AiOperations.log(%{
      run_stream_id: correlation_id,
      kind: "chat",
      payload: text
    })

    case @llm.chat(system, messages) do
      {:ok, reply, _usage} ->
        AiOperations.log(%{
          run_stream_id: "#{correlation_id}:reply",
          kind: "chat_reply",
          payload: text,
          result: reply
        })

        {:ok, reply, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
