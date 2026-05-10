defmodule Scullion.Adapters.OpenRouter do
  @behaviour Scullion.LLM
  @behaviour Scullion.ImageGen

  @api_url "https://openrouter.ai/api/v1/chat/completions"

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
  def suggest_slot_recipe(context) do
    {system, user} = Scullion.LLM.Prompts.suggest_slot_recipe(context)

    case chat(system, user) do
      {:ok, %{"recipe_id" => rid} = data, usage} when is_integer(rid) ->
        candidate_ids = MapSet.new(context.candidate_recipe_ids || [])

        if MapSet.member?(candidate_ids, rid) do
          {:ok, %{recipe_id: rid, reasoning: data["reasoning"] || ""}, usage}
        else
          {:error, :hallucinated_recipe}
        end

      {:ok, _other, _usage} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Scullion.LLM
  def extract_recipe_from_html(html) do
    {system, user} = Scullion.LLM.Prompts.extract_recipe(html)

    case chat(system, user) do
      {:ok, data, _usage} -> {:ok, parse_recipe_attrs(data)}
      {:error, reason} -> {:error, reason}
    end
  end

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

  @impl Scullion.LLM
  def parse_recipe_images(images) do
    system = Scullion.LLM.Prompts.parse_recipe_images()

    image_blocks =
      Enum.map(images, fn binary ->
        b64 = Base.encode64(binary)
        %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{b64}"}}
      end)

    body = %{
      model: vision_model(),
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: image_blocks}
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

        with {:ok, data} <- Jason.decode(content) do
          {:ok, parse_recipe_attrs(data)}
        end

      {:ok, %{status: 402}} -> {:error, :provider_budget_exceeded}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status, body: resp}} -> {:error, {:openrouter_error, status, resp}}
      {:error, reason} -> {:error, {:http_error, reason}}
    end
  end

  @impl Scullion.ImageGen
  def generate_food_image(title, recipe_text) do
    context = if recipe_text && recipe_text != "", do: "\n\nRecipe context:\n#{recipe_text}", else: ""

    prompt =
      "Food photography, overhead shot, natural light, #{title}.#{context} " <>
        "Clean white plate, rustic wooden table, appetizing, high resolution."

    body = %{
      model: image_model(),
      modalities: ["image"],
      messages: [%{role: "user", content: prompt}]
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
        data_url =
          get_in(resp, ["choices", Access.at(0), "message", "images", Access.at(0), "image_url", "url"])

        case data_url do
          "data:" <> _ ->
            [_prefix, b64] = String.split(data_url, ",", parts: 2)
            {:ok, Base.decode64!(b64)}

          nil ->
            {:error, :no_image_returned}
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

  defp parse_recipe_attrs(data) do
    raw_steps = data["steps"] || []

    # Sort by order unconditionally — don't trust the LLM to get phase grouping right
    steps = Enum.sort_by(raw_steps, & &1["order"])

    instructions =
      steps
      |> Enum.chunk_by(& &1["phase"])
      |> Enum.map(fn phase_steps ->
        phase = hd(phase_steps)["phase"]
        lines = Enum.map(phase_steps, fn s -> "#{s["order"]}. #{s["action"]}" end) |> Enum.join("\n")
        "#{phase}:\n#{lines}"
      end)
      |> Enum.join("\n\n")

    %{
      title: data["title"],
      description: data["description"],
      prep_time_minutes: data["prep_time_minutes"],
      cook_time_minutes: data["cook_time_minutes"],
      base_servings: data["base_servings"],
      image_url: data["image_url"],
      ingredients: parse_ingredients(data["ingredients"] || []),
      tags: data["tags"] || [],
      steps: if(steps == [], do: nil, else: Jason.encode!(steps)),
      instructions: if(instructions == "", do: nil, else: instructions)
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp parse_ingredients(list) do
    Enum.map(list, fn item ->
      %{name: item["item"] || item["name"], quantity: parse_decimal(item["quantity"]), unit: item["unit"]}
    end)
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(n) when is_number(n), do: Decimal.from_float(n * 1.0)
  defp parse_decimal(s) when is_binary(s), do: Decimal.new(s)

  defp api_key, do: Application.fetch_env!(:scullion, :openrouter_api_key)
  defp model, do: Application.get_env(:scullion, :openrouter_model, "deepseek/deepseek-v4-flash")
  defp vision_model, do: Application.get_env(:scullion, :openrouter_vision_model, "google/gemini-2.5-flash-lite")
  defp image_model, do: Application.get_env(:scullion, :openrouter_image_model, "google/gemini-2.5-flash-image")
end
