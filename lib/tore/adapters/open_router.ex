defmodule Tore.Adapters.OpenRouter do
  @behaviour Tore.LLM
  @behaviour Tore.ImageGen

  @api_url "https://openrouter.ai/api/v1/chat/completions"

  @impl Tore.LLM
  def generate_plan(constraints) do
    {system, user} = Tore.LLM.Prompts.plan_weekly(constraints)
    chat(system, user)
  end

  @impl Tore.LLM
  def generate_prep_guide(plan, locale \\ nil) do
    {system, user} = Tore.LLM.Prompts.prep_guide(plan, locale)
    chat(system, user)
  end

  @impl Tore.LLM
  def suggest_recipes(_context), do: {:error, :not_implemented}

  @impl Tore.LLM
  def suggest_slot_recipe(context) do
    {system, user} = Tore.LLM.Prompts.suggest_slot_recipe(context)

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

  @impl Tore.LLM
  def extract_recipe_from_html(html, locale \\ nil) do
    with :ok <- check_parseable(html) do
      {system, user} = Tore.LLM.Prompts.extract_recipe(html, locale)

      case chat(system, user, Tore.LLM.Prompts.recipe_json_schema()) do
        {:ok, data, _usage} -> {:ok, parse_recipe_attrs(data)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl Tore.LLM
  def parse_receipt_image(image_binary) do
    {system, user_text} = Tore.LLM.Prompts.parse_receipt()
    b64 = Base.encode64(image_binary)

    body = %{
      model: vision_model(),
      response_format: Tore.LLM.Prompts.receipt_json_schema(),
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
             {"X-Title", "Tore"}
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
                total_price: parse_decimal(item["total_price"]),
                category: item["category"]
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

  @impl Tore.LLM
  def parse_pantry_image(image_binary) do
    {system, user_text} = Tore.LLM.Prompts.parse_pantry_image()
    b64 = Base.encode64(image_binary)

    body = %{
      model: vision_model(),
      response_format: Tore.LLM.Prompts.pantry_json_schema(),
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
             {"X-Title", "Tore"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(resp)

        with {:ok, parsed} <- Jason.decode(content) do
          items =
            Enum.map(parsed["items"] || [], fn item ->
              %{
                name: item["name"],
                quantity: parse_decimal(item["quantity"]),
                unit: item["unit"],
                category: item["category"]
              }
            end)

          {:ok, items, usage}
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

  @impl Tore.LLM
  def parse_receipt_for_pantry(image_binary) do
    {system, user_text} = Tore.LLM.Prompts.parse_receipt_for_pantry()
    b64 = Base.encode64(image_binary)

    body = %{
      model: vision_model(),
      response_format: Tore.LLM.Prompts.receipt_pantry_json_schema(),
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
             {"X-Title", "Tore"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(resp)

        with {:ok, parsed} <- Jason.decode(content) do
          items =
            Enum.map(parsed["items"] || [], fn item ->
              %{
                name: item["name"],
                quantity: parse_decimal(item["quantity"]),
                unit: item["unit"],
                category: item["category"]
              }
            end)

          result = %{
            total: parse_decimal(parsed["total"]),
            store_name: parsed["store_name"],
            items: items
          }

          {:ok, result, usage}
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

  @impl Tore.LLM
  def estimate_nutrition(%{title: title, ingredients: ingredients}) do
    {system, _} = Tore.LLM.Prompts.estimate_nutrition()
    user = "Recipe: #{title}\nIngredients: #{Enum.join(ingredients, ", ")}"
    chat(system, user)
  end

  def estimate_nutrition(_), do: {:error, :invalid_recipe}

  @impl Tore.LLM
  def filter_pantry_items(ingredients, pantry) do
    {system, user} = Tore.LLM.Prompts.filter_pantry_items(ingredients, pantry)

    case cheap_chat(system, user, check_model_fallback(), Tore.LLM.Prompts.filter_pantry_schema()) do
      {:ok, resp, _usage} when is_list(resp) ->
        build_filter_result(resp)

      {:ok, %{"items" => items}, _usage} when is_list(items) ->
        build_filter_result(items)

      {:ok, _, _} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Tore.LLM
  def classify_grocery_item(name) do
    {system, user} = Tore.LLM.Prompts.classify_grocery_item(name)

    case cheap_chat(system, user, model()) do
      {:ok, %{"section" => section}, _usage} -> {:ok, to_section_atom(section)}
      {:ok, _, _} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Tore.LLM
  def parse_deals_image(_image), do: {:error, :not_implemented}

  @impl Tore.LLM
  def parse_deals_pdf(pdf_binary) do
    {system, user_text} = Tore.LLM.Prompts.parse_deals_pdf()
    b64 = Base.encode64(pdf_binary)

    body = %{
      model: vision_model(),
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: system},
        %{
          role: "user",
          content: [
            %{type: "text", text: user_text},
            %{
              type: "file",
              file: %{filename: "deals.pdf", file_data: "data:application/pdf;base64,#{b64}"}
            }
          ]
        }
      ]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key()}"},
             {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
             {"X-Title", "Tore"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])

        with {:ok, parsed} <- decode_content(content) do
          raw_deals =
            cond do
              is_list(parsed) -> parsed
              is_map(parsed) -> parsed["deals"] || []
              true -> []
            end

          deals =
            Enum.map(raw_deals, fn d ->
              %{
                chain: d["chain"] || "other",
                store: d["store"] || d["chain"] || "other",
                product_name: d["product_name"],
                brand: d["brand"],
                size: d["size"],
                price: parse_decimal(d["price"]),
                price_unit: d["price_unit"],
                offer_condition: d["offer_condition"],
                regular_price: d["regular_price"],
                comparison_price: d["comparison_price"],
                valid_from: parse_date(d["valid_from"]),
                valid_until: parse_date(d["valid_until"]),
                source: :vision
              }
            end)

          {:ok, deals}
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

  @impl Tore.LLM
  def parse_recipe_images(images, locale \\ nil) do
    system = Tore.LLM.Prompts.parse_recipe_images(locale)

    image_blocks =
      Enum.map(images, fn binary ->
        b64 = Base.encode64(binary)
        %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{b64}"}}
      end)

    body = %{
      model: vision_model(),
      response_format: Tore.LLM.Prompts.recipe_json_schema(),
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
             {"X-Title", "Tore"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])

        with {:ok, data} <- Jason.decode(content) do
          {:ok, parse_recipe_attrs(data)}
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

    case Req.post(@api_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key()}"},
             {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
             {"X-Title", "Tore"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
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

  defp check_parseable(html) do
    {system, user} = Tore.LLM.Prompts.check_recipe_html(html)

    result =
      case cheap_chat(system, user, check_model()) do
        {:ok, %{"parseable" => true}, _} -> :ok
        {:ok, %{"parseable" => false}, _} -> {:error, :not_a_recipe}
        {:error, _} -> cheap_chat(system, user, check_model_fallback())
      end

    case result do
      :ok -> :ok
      {:ok, %{"parseable" => true}, _} -> :ok
      {:ok, %{"parseable" => false}, _} -> {:error, :not_a_recipe}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cheap_chat(system_prompt, user_prompt, model_name, response_format \\ %{type: "json_object"}) do
    body = %{
      model: model_name,
      response_format: response_format,
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
             {"X-Title", "Tore"}
           ]
         ) do
      {:ok, %{status: 200, body: resp}} ->
        content = get_in(resp, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(resp)

        with {:ok, parsed} <- Jason.decode(content) do
          {:ok, parsed, usage}
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

  defp chat(system_prompt, user_prompt, response_format \\ %{type: "json_object"}) do
    body = %{
      model: model(),
      response_format: response_format,
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
             {"X-Title", "Tore"}
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

        lines =
          Enum.map(phase_steps, fn s -> "#{s["order"]}. #{s["action"]}" end) |> Enum.join("\n")

        "## #{phase}\n\n#{lines}"
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
      %{
        name: item["item"] || item["name"],
        quantity: parse_decimal(item["quantity"]),
        unit: item["unit"]
      }
    end)
  end

  defp decode_content(content) when is_binary(content), do: Jason.decode(content)
  defp decode_content(content) when is_map(content) or is_list(content), do: {:ok, content}
  defp decode_content(_), do: {:error, :no_content}

  defp parse_date(nil), do: nil

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp build_filter_result(items) do
    result =
      items
      |> Enum.map(fn i -> Map.put(i, "name", i["name"] || i["item"] || i["ingredient"]) end)
      |> Enum.filter(&is_binary(&1["name"]))
      |> Enum.map(fn i ->
        qty = case i["quantity"] do
          nil -> nil
          n when is_number(n) -> n
          s when is_binary(s) -> s
          _ -> nil
        end

        %{
          id: Ecto.UUID.generate(),
          name: i["name"],
          quantity: qty,
          unit: i["unit"],
          section: to_section_atom(i["section"]),
          checked: false
        }
      end)

    {:ok, result}
  end

  @valid_sections ~w(produce meat fish dairy deli frozen bread dry_goods canned beverages herbs_spices condiments household other)

  defp to_section_atom(s) when is_binary(s) and s in @valid_sections, do: String.to_atom(s)
  defp to_section_atom(_), do: :other

  defp parse_decimal(nil), do: nil
  defp parse_decimal(n) when is_number(n), do: Decimal.from_float(n * 1.0)
  defp parse_decimal(s) when is_binary(s), do: Decimal.new(s)

  defp api_key, do: Application.fetch_env!(:tore, :openrouter_api_key)
  defp model, do: Application.get_env(:tore, :openrouter_model, "openai/gpt-5-mini")

  defp vision_model,
    do: Application.get_env(:tore, :openrouter_vision_model, "google/gemini-2.5-flash-lite")

  defp image_model,
    do:
      Application.get_env(:tore, :openrouter_image_model, "google/gemini-3.1-flash-image-preview")

  defp check_model,
    do: Application.get_env(:tore, :openrouter_check_model, "openai/gpt-oss-120b:free")

  defp check_model_fallback,
    do: Application.get_env(:tore, :openrouter_check_model_fallback, "openai/gpt-oss-120b")
end
