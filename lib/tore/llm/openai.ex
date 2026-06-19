defmodule Tore.LLM.OpenAI do
  @moduledoc """
  OpenAI-flavoured wire spec implementation of `Tore.LLM.Spec`.

  Pure: builds the OpenAI `chat/completions` body, hands it to the injected
  `Tore.Adapter` for transport, decodes the response. No I/O.

  Talks to whatever provider speaks OpenAI shape via the adapter
  (OpenRouter, OpenAI, Together, Groq, Fireworks, etc.).
  """

  @behaviour Tore.LLM.Spec

  @impl true
  def text(system, user, opts) do
    %{
      model: Keyword.get(opts, :model, model()),
      response_format: Keyword.get(opts, :response_format, %{type: "json_object"}),
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ]
    }
    |> adapter().request()
    |> decode_json()
  end

  @impl true
  def vision(blobs, system, user, opts) when is_list(blobs) do
    %{
      model: Keyword.get(opts, :model, vision_model()),
      response_format: Keyword.get(opts, :response_format, %{type: "json_object"}),
      messages: [
        %{role: "system", content: system},
        %{
          role: "user",
          content: [%{type: "text", text: user} | Enum.map(blobs, &blob_to_part/1)]
        }
      ]
    }
    |> adapter().request()
    |> decode_json()
  end

  @impl true
  def chat(system, messages, opts) do
    %{
      model: Keyword.get(opts, :model, model()),
      messages: [%{role: "system", content: system} | messages]
    }
    |> adapter().request()
    |> case do
      {:ok, resp} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        {:ok, content, extract_usage(resp)}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def chat_with_tools(system, messages, tools, opts) do
    body =
      %{
        model: Keyword.get(opts, :model, model()),
        messages: [%{role: "system", content: system} | messages],
        tools: tools
      }
      |> maybe_put_tool_choice(tools, opts)

    case adapter().request(body) do
      {:ok, resp} ->
        msg = get_in(resp, ["choices", Access.at(0), "message"]) || %{}
        usage = extract_usage(resp)

        case msg do
          %{"tool_calls" => calls} when is_list(calls) and calls != [] ->
            {:ok, {:tool_calls, Enum.map(calls, &decode_tool_call/1)}, usage}

          %{"content" => content} when is_binary(content) ->
            {:ok, {:message, content}, usage}

          _ ->
            {:error, {:unexpected_message, msg}}
        end

      {:error, _} = err ->
        err
    end
  end

  # ---- Private decoding ---------------------------------------------------

  defp decode_json({:ok, resp}) do
    content = get_in(resp, ["choices", Access.at(0), "message", "content"])
    usage = extract_usage(resp)

    case decode_content(content) do
      {:ok, parsed} -> {:ok, parsed, usage}
      {:error, _} = err -> err
    end
  end

  defp decode_json({:error, _} = err), do: err

  defp decode_content(content) when is_binary(content), do: Jason.decode(content)
  defp decode_content(content) when is_map(content) or is_list(content), do: {:ok, content}
  defp decode_content(_), do: {:error, :no_content}

  defp extract_usage(%{"usage" => usage}) when is_map(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      cost_usd: usage["cost"] || 0.0
    }
  end

  defp extract_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: 0.0}

  defp blob_to_part({:image, bin}) do
    %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{Base.encode64(bin)}"}}
  end

  defp blob_to_part({:pdf, bin}) do
    %{
      type: "file",
      file: %{filename: "doc.pdf", file_data: "data:application/pdf;base64,#{Base.encode64(bin)}"}
    }
  end

  defp maybe_put_tool_choice(body, [], _opts), do: body

  defp maybe_put_tool_choice(body, _tools, opts) do
    Map.put(body, :tool_choice, Keyword.get(opts, :tool_choice, "auto"))
  end

  defp decode_tool_call(%{"id" => id, "function" => %{"name" => name, "arguments" => raw_args}}) do
    args =
      case Jason.decode(raw_args || "{}") do
        {:ok, m} when is_map(m) -> m
        _ -> %{}
      end

    %{id: id, name: name, args: args}
  end

  defp decode_tool_call(other) when is_map(other) do
    %{
      id: Map.get(other, "id", ""),
      name: get_in(other, ["function", "name"]) || "",
      args: %{}
    }
  end

  # ---- Config -------------------------------------------------------------

  defp adapter, do: Application.get_env(:tore, :llm_adapter, Tore.Adapters.OpenRouter)
  defp model, do: Application.get_env(:tore, :openrouter_model, "openai/gpt-5-mini")

  defp vision_model,
    do: Application.get_env(:tore, :openrouter_vision_model, "google/gemini-3.1-flash-lite")
end
