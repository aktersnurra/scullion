defmodule Tore.Adapters.OpenRouter do
  @moduledoc """
  OpenRouter transport. Sends a chat-completions body, returns the raw
  response or a normalised error. No body construction, no decoding.
  """

  @behaviour Tore.Adapter
  @behaviour Tore.ImageGen

  @api_url "https://openrouter.ai/api/v1/chat/completions"

  # Bound the model call so a stuck upstream can't wedge the caller.
  # 120s covers slow vision + cold-start on Vertex; tune via opts if needed.
  @receive_timeout_ms 120_000
  @connect_timeout_ms 10_000

  @impl Tore.Adapter
  def request(body) do
    Req.post(@api_url,
      json: body,
      headers: headers(),
      receive_timeout: @receive_timeout_ms,
      connect_options: [timeout: @connect_timeout_ms]
    )
    |> case do
      {:ok, %{status: 200, body: resp}} -> {:ok, resp}
      {:ok, %{status: 402}} -> {:error, :provider_budget_exceeded}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status, body: resp}} -> {:error, {:openrouter_error, status, resp}}
      {:error, reason} -> {:error, {:http_error, reason}}
    end
  end

  @impl Tore.ImageGen
  def generate_food_image(title, recipe_text) do
    context =
      if recipe_text && recipe_text != "", do: "\n\nRecipe context:\n#{recipe_text}", else: ""

    prompt =
      "Food photography, overhead shot, natural light, #{title}.#{context} " <>
        "Clean white plate, rustic wooden table, appetizing, high resolution."

    body = %{
      model: image_model(),
      modalities: ["image"],
      messages: [%{role: "user", content: prompt}]
    }

    case request(body) do
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

  defp headers do
    [
      {"Authorization", "Bearer #{api_key()}"},
      {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
      {"X-Title", "Tore"}
    ]
  end

  defp api_key, do: Application.fetch_env!(:tore, :openrouter_api_key)

  defp image_model,
    do:
      Application.get_env(:tore, :openrouter_image_model, "google/gemini-3.1-flash-image-preview")
end
