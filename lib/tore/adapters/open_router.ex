defmodule Tore.Adapters.OpenRouter do
  @moduledoc """
  Transport adapter for OpenRouter chat-completions.

  Three behaviour callbacks (`text/3`, `vision/4`, `chat/2`, `chat_with_tools/4`)
  plus image generation. No domain shaping happens here — callers receive the
  raw decoded JSON (or string) and shape it themselves.
  """

  @behaviour Tore.LLM
  @behaviour Tore.ImageGen

  @api_url "https://openrouter.ai/api/v1/chat/completions"

  @impl Tore.LLM
  def text(system, user, opts \\ []) do
    %{
      model: Keyword.get(opts, :model, model()),
      response_format: Keyword.get(opts, :response_format, %{type: "json_object"}),
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ]
    }
    |> request_json()
  end

  @impl Tore.LLM
  def vision(blobs, system, user, opts \\ []) when is_list(blobs) do
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
    |> request_json()
  end

  @impl Tore.LLM
  def chat(system, messages) do
    %{
      model: model(),
      messages: [%{role: "system", content: system} | messages]
    }
    |> request_raw()
    |> case do
      {:ok, resp} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        {:ok, content, extract_usage(resp)}

      {:error, _} = err ->
        err
    end
  end

  @impl Tore.LLM
  def chat_with_tools(system, messages, tools, opts) do
    body =
      %{
        model: Keyword.get(opts, :model, model()),
        messages: [%{role: "system", content: system} | messages],
        tools: tools
      }
      |> maybe_put_tool_choice(tools, opts)

    http = Application.get_env(:tore, :http_client, Tore.Adapters.ReqHTTP)

    case http.post(@api_url, json: body, headers: headers()) do
      {:ok, %{status: 200, body: resp}} ->
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

      result ->
        normalise_error(result)
    end
  end

  @impl Tore.ImageGen
  def generate_food_image(title, recipe_text) do
    context =
      if recipe_text && recipe_text != "", do: "\n\nRecipe context:\n#{recipe_text}", else: ""

    prompt =
      "Food photography, overhead shot, natural light, #{title}.#{context} " <>
        "Clean white plate, rustic wooden table, appetizing, high resolution."

    %{
      model: image_model(),
      modalities: ["image"],
      messages: [%{role: "user", content: prompt}]
    }
    |> request_raw()
    |> case do
      {:ok, resp} ->
        data_url =
          get_in(resp, [
            "choices",
            Access.at(0),
            "message",
            "images",
            Access.at(0),
            "image_url",
            "url"
          ])

        case data_url do
          "data:" <> _ ->
            [_prefix, b64] = String.split(data_url, ",", parts: 2)
            {:ok, Base.decode64!(b64)}

          nil ->
            {:error, :no_image_returned}
        end

      {:error, _} = err ->
        err
    end
  end

  # ----- HTTP primitive ------------------------------------------------------

  defp request_json(body) do
    case request_raw(body) do
      {:ok, resp} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(resp)

        case decode_content(content) do
          {:ok, parsed} -> {:ok, parsed, usage}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp request_raw(body) do
    case Req.post(@api_url, json: body, headers: headers()) do
      {:ok, %{status: 200, body: resp}} -> {:ok, resp}
      result -> normalise_error(result)
    end
  end

  defp normalise_error({:ok, %{status: 402}}), do: {:error, :provider_budget_exceeded}
  defp normalise_error({:ok, %{status: 429}}), do: {:error, :rate_limited}
  defp normalise_error({:ok, %{status: status, body: resp}}),
    do: {:error, {:openrouter_error, status, resp}}

  defp normalise_error({:error, reason}), do: {:error, {:http_error, reason}}

  defp headers do
    [
      {"Authorization", "Bearer #{api_key()}"},
      {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
      {"X-Title", "Tore"}
    ]
  end

  defp blob_to_part({:image, bin}) do
    %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{Base.encode64(bin)}"}}
  end

  defp blob_to_part({:pdf, bin}) do
    %{
      type: "file",
      file: %{filename: "doc.pdf", file_data: "data:application/pdf;base64,#{Base.encode64(bin)}"}
    }
  end

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

  # ----- Config --------------------------------------------------------------

  defp api_key, do: Application.fetch_env!(:tore, :openrouter_api_key)
  defp model, do: Application.get_env(:tore, :openrouter_model, "openai/gpt-5-mini")

  defp vision_model,
    do: Application.get_env(:tore, :openrouter_vision_model, "google/gemini-3.1-flash-lite")

  defp image_model,
    do:
      Application.get_env(:tore, :openrouter_image_model, "google/gemini-3.1-flash-image-preview")
end
