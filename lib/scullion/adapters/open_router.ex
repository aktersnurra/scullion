defmodule Scullion.Adapters.OpenRouter do
  @behaviour Scullion.LLM
  @behaviour Scullion.ImageGen

  @api_url "https://openrouter.ai/api/v1/chat/completions"
  @image_api_url "https://openrouter.ai/api/v1/images/generations"

  @impl Scullion.LLM
  def generate_plan(constraints) do
    {system, user} = Scullion.LLM.Prompts.plan_weekly(constraints)
    chat(system, user)
  end

  @impl Scullion.LLM
  def generate_prep_guide(plan) do
    {system, user} = Scullion.LLM.Prompts.prep_guide(plan)
    chat(system, user)
  end

  @impl Scullion.LLM
  def suggest_recipes(_context), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def extract_recipe_from_html(_html), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def parse_receipt_image(image_binary) do
    {system, user_text} = Scullion.LLM.Prompts.parse_receipt()
    b64 = Base.encode64(image_binary)

    body = %{
      model: vision_model(),
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: system},
        %{
          role: "user",
          content: [
            %{type: "text", text: user_text},
            %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{b64}"}}
          ]
        }
      ]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key()}"},
             {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
             {"X-Title", "Scullion"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(resp)

        with {:ok, parsed} <- Jason.decode(content) do
          line_items =
            Enum.map(parsed["line_items"] || [], fn item ->
              %{
                product_name: item["product_name"],
                quantity: parse_decimal(item["quantity"]),
                unit_price: parse_decimal(item["unit_price"]),
                total_price: parse_decimal(item["total_price"])
              }
            end)

          {:ok, line_items, usage}
        end

      {:ok, %{status: 402}} ->
        {:error, :provider_budget_exceeded}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: resp}} ->
        {:error, {:openrouter_error, status, resp}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  @impl Scullion.LLM
  def estimate_nutrition(%{title: title, ingredients: ingredients}) do
    {system, _} = Scullion.LLM.Prompts.estimate_nutrition()
    user = "Recipe: #{title}\nIngredients: #{Enum.join(ingredients, ", ")}"
    chat(system, user)
  end

  def estimate_nutrition(_), do: {:error, :invalid_recipe}

  @impl Scullion.LLM
  def parse_deals_image(_image), do: {:error, :not_implemented}

  @impl Scullion.ImageGen
  def generate_food_image(title, ingredients) do
    prompt =
      "Food photography, overhead shot, natural light, #{title} made with #{Enum.join(ingredients, ", ")}. " <>
        "Clean white plate, rustic wooden table, appetizing, high resolution."

    body = %{
      model: image_model(),
      prompt: prompt,
      n: 1,
      size: "512x512",
      response_format: "b64_json"
    }

    case Req.post(@image_api_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key()}"},
             {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
             {"X-Title", "Scullion"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        b64 = get_in(resp, ["data", Access.at(0), "b64_json"])

        case b64 do
          nil -> {:error, :no_image_returned}
          _ -> {:ok, Base.decode64!(b64)}
        end

      {:ok, %{status: 402}} ->
        {:error, :provider_budget_exceeded}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: resp}} ->
        {:error, {:openrouter_error, status, resp}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp chat(system_prompt, user_prompt) do
    body = %{
      model: model(),
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_prompt}
      ]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key()}"},
             {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
             {"X-Title", "Scullion"}
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(body)

        with {:ok, parsed} <- Jason.decode(content) do
          {:ok, parsed, usage}
        end

      {:ok, %{status: 402}} ->
        {:error, :provider_budget_exceeded}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        {:error, {:openrouter_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp extract_usage(%{"usage" => usage}) when is_map(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      cost_usd: usage["cost"] || 0.0
    }
  end

  defp extract_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: 0.0}

  defp parse_decimal(nil), do: nil
  defp parse_decimal(n) when is_number(n), do: Decimal.from_float(n * 1.0)
  defp parse_decimal(s) when is_binary(s), do: Decimal.new(s)

  defp api_key, do: Application.fetch_env!(:scullion, :openrouter_api_key)
  defp model, do: Application.get_env(:scullion, :openrouter_model, "anthropic/claude-3-5-haiku")
  defp vision_model, do: Application.get_env(:scullion, :openrouter_vision_model, "google/gemini-flash-1.5")
  defp image_model, do: Application.get_env(:scullion, :openrouter_image_model, "black-forest-labs/flux-schnell")
end
