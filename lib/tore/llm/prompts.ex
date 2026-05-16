defmodule Tore.LLM.Prompts do
  @prompts_dir Path.join(:code.priv_dir(:tore), "llm/prompts")

  def suggest_slot_recipe(context) do
    dietary = dietary_guidance_instruction(context[:dietary_guidance])

    system = """
    You are a meal planner suggesting one recipe for a single dinner slot.
    Goal: pick the best fit from the candidate recipes given week context.
    Principles:
    - Reuse ingredients from neighboring meals
    - Prefer pantry items and current deals
    - Avoid recipes already cooked this week
    - Match the day's available time and energy#{dietary}
    You MUST pick a recipe_id from the provided candidate list.
    Respond ONLY with JSON: {"recipe_id": <int>, "reasoning": "<one short sentence>"}.
    """

    user = render("suggest_slot_recipe.eex", context)
    {system, user}
  end

  def plan_weekly(constraints) do
    dietary = dietary_guidance_instruction(constraints[:dietary_guidance])

    system = """
    You are a meal planner. Think like a prep cook.
    Goal: assign recipes to meal slots for the week.
    Principles:
    - Batch cook early in the week; cascade leftovers into later meals
    - Prefer ingredient reuse over variety
    - Respect pinned slots as hard constraints
    - Prefer pantry items and deals when available
    - Weeknight slots need recipes with total time ≤45 min#{dietary}
    Respond with a JSON object only. No prose.
    """

    user = render("plan_weekly.eex", constraints)
    {system, user}
  end

  def prep_guide(plan, locale \\ nil) do
    system = """
    You are a sous chef. Generate a Sunday prep session guide for the week's meals.
    Think in cascades: prep components that transform into different dishes across the week.
    Respond with a JSON object only. No prose.#{translation_instruction(locale)}
    """

    user = render("prep_guide.eex", plan)
    {system, user}
  end

  def estimate_nutrition do
    system = File.read!(Path.join(@prompts_dir, "estimate_nutrition.eex"))
    {system, ""}
  end

  @recipe_schema """
  {
    "title": "string (required)",
    "description": "string or null",
    "prep_time_minutes": "integer or null",
    "cook_time_minutes": "integer or null",
    "base_servings": "integer or null",
    "image_url": "absolute URL string or null",
    "tags": ["string"],
    "ingredients": [
      { "item": "string", "quantity": "number or null", "unit": "string or null" }
    ],
    "steps": [
      {
        "phase": "string — cooking phase name in ALL CAPS (e.g. MISE EN PLACE, SAUCE, ASSEMBLY, COOKING, BAKING)",
        "order": "integer — global step number starting at 1",
        "action": "string — one clear, atomic cooking action",
        "ingredients": ["string — ingredient names used in this step"],
        "duration_minutes": "integer or null — only if this step has an explicit wait/cook time"
      }
    ]
  }
  """

  @recipe_json_schema %{
    type: "object",
    required: ["title", "ingredients", "steps", "tags"],
    additionalProperties: false,
    properties: %{
      title: %{type: "string"},
      description: %{type: ["string", "null"]},
      prep_time_minutes: %{type: ["integer", "null"]},
      cook_time_minutes: %{type: ["integer", "null"]},
      base_servings: %{type: ["integer", "null"]},
      image_url: %{type: ["string", "null"]},
      tags: %{type: "array", items: %{type: "string"}},
      ingredients: %{
        type: "array",
        items: %{
          type: "object",
          required: ["item"],
          additionalProperties: false,
          properties: %{
            item: %{type: "string"},
            quantity: %{type: ["number", "null"]},
            unit: %{type: ["string", "null"]}
          }
        }
      },
      steps: %{
        type: "array",
        items: %{
          type: "object",
          required: ["phase", "order", "action", "ingredients"],
          additionalProperties: false,
          properties: %{
            phase: %{type: "string"},
            order: %{type: "integer"},
            action: %{type: "string"},
            ingredients: %{type: "array", items: %{type: "string"}},
            duration_minutes: %{type: ["integer", "null"]}
          }
        }
      }
    }
  }

  def recipe_json_schema do
    %{
      type: "json_schema",
      json_schema: %{name: "recipe", strict: true, schema: @recipe_json_schema}
    }
  end

  @recipe_rules """
  - title is required; steps and ingredients must always be arrays (empty if unknown)
  - CRITICAL: the steps array must be sorted in the exact order a cook performs them, start to finish
  - The "order" field is a single global counter: the first thing you do is order 1, the second is order 2, etc.
  - MISE EN PLACE (prep) always comes before any cooking phase — assign it the lowest order numbers
  - Cooking phases follow in the order they are actually executed, not the order they appear in the source
  - Example of correct ordering for a meatball recipe:
      order 1 phase "MISE EN PLACE" — chop onion
      order 2 phase "MISE EN PLACE" — mix meat and breadcrumbs
      order 3 phase "COOKING" — fry meatballs
      order 4 phase "SAUCE" — make sauce in same pan
      order 5 phase "SERVING" — plate with sides
  - each step is one atomic action — never combine multiple actions in one step
  - do not summarise or skip any steps from the source
  - reference ingredient names in each step's ingredients array exactly as they appear in the top-level ingredients list
  - ingredients: list every ingredient with "item" (name), "quantity" (number or null), "unit" (string or null, e.g. "g", "ml", "dl", "st", "msk", "tsk") — use null when not specified
  - tags: 1-3 lowercase tags (cuisine, main protein, or style — e.g. "chicken", "italian", "quick", "vegetarian")
  - Respond with a JSON object only. No prose.
  """

  def extract_recipe(html, locale \\ nil) do
    system = """
    You are a recipe extractor. Given raw HTML from a recipe webpage, extract the recipe.
    Return a JSON object matching this exact structure:
    #{@recipe_schema}
    Rules:
    #{@recipe_rules}
    #{translation_instruction(locale)}
    """

    {system, html}
  end

  def parse_recipe_images(locale \\ nil) do
    """
    You are a recipe extractor. The user has photographed one or more pages of a recipe — ingredients may be on one image, instructions on another.
    Combine all images into a single complete recipe and return a JSON object matching this exact structure:
    #{@recipe_schema}
    Rules:
    #{@recipe_rules}
    #{translation_instruction(locale)}
    """
  end

  @locale_names %{
    "sv" => "Swedish",
    "en" => "English",
    "de" => "German",
    "fr" => "French",
    "es" => "Spanish",
    "no" => "Norwegian",
    "da" => "Danish",
    "fi" => "Finnish"
  }

  defp translation_instruction(nil), do: ""

  defp translation_instruction(locale) do
    case Map.get(@locale_names, locale) do
      nil ->
        ""

      language ->
        "- Translate ALL text fields (title, description, tags, step phases, step actions, ingredient names) into #{language}. Keep units as-is (g, ml, msk, tsk, etc.)."
    end
  end

  @receipt_json_schema %{
    type: "object",
    required: ["line_items"],
    additionalProperties: false,
    properties: %{
      line_items: %{
        type: "array",
        items: %{
          type: "object",
          required: ["product_name", "category"],
          additionalProperties: false,
          properties: %{
            product_name: %{type: "string"},
            quantity: %{type: ["number", "null"]},
            unit_price: %{type: ["number", "null"]},
            total_price: %{type: ["number", "null"]},
            category: %{
              type: "string",
              enum: ["dairy", "meat", "produce", "frozen", "dry_goods", "canned", "herbs_spices", "condiments", "other"]
            }
          }
        }
      }
    }
  }

  def receipt_json_schema do
    %{
      type: "json_schema",
      json_schema: %{name: "receipt", strict: true, schema: @receipt_json_schema}
    }
  end

  def check_recipe_html(html) do
    system = """
    You are a recipe detector. Does the provided HTML contain a parseable recipe with ingredients and instructions?
    Respond ONLY with JSON: {"parseable": true} or {"parseable": false}.
    """

    user = String.slice(html, 0, 2000)
    {system, user}
  end

  @pantry_json_schema %{
    type: "object",
    required: ["items"],
    additionalProperties: false,
    properties: %{
      items: %{
        type: "array",
        items: %{
          type: "object",
          required: ["name"],
          additionalProperties: false,
          properties: %{
            name: %{type: "string"},
            quantity: %{type: ["number", "null"]},
            unit: %{type: ["string", "null"]},
            category: %{type: ["string", "null"]}
          }
        }
      }
    }
  }

  def pantry_json_schema do
    %{
      type: "json_schema",
      json_schema: %{name: "pantry_items", strict: true, schema: @pantry_json_schema}
    }
  end

  def parse_pantry_image do
    system = """
    You are a kitchen inventory assistant. Identify food and household items from photos.
    Respond with a JSON object only. No prose.
    """

    user = File.read!(Path.join(@prompts_dir, "parse_pantry_image.eex"))
    {system, user}
  end

  def parse_receipt do
    system = """
    You are a receipt parser. Extract line items from receipt images precisely.
    Respond with a JSON object only. No prose.
    """

    user = File.read!(Path.join(@prompts_dir, "parse_receipt.eex"))
    {system, user}
  end

  @receipt_pantry_json_schema %{
    type: "object",
    required: ["total", "store_name", "items"],
    additionalProperties: false,
    properties: %{
      total: %{type: ["number", "null"]},
      store_name: %{type: ["string", "null"]},
      items: %{
        type: "array",
        items: %{
          type: "object",
          required: ["name"],
          additionalProperties: false,
          properties: %{
            name: %{type: "string"},
            quantity: %{type: ["number", "null"]},
            unit: %{type: ["string", "null"]},
            category: %{type: ["string", "null"]}
          }
        }
      }
    }
  }

  def receipt_pantry_json_schema do
    %{
      type: "json_schema",
      json_schema: %{name: "receipt_pantry", strict: true, schema: @receipt_pantry_json_schema}
    }
  end

  def parse_receipt_for_pantry do
    system = """
    You are a receipt parser. Given a photo of a grocery receipt:
    1. Extract the store name (if visible).
    2. Extract the total amount paid (the final total, in the receipt's currency).
    3. Extract each purchased grocery item as a pantry entry with name, quantity, and unit.
       - Omit non-food items like bags, fees, or deposits unless clearly a food product.
       - Use standard Swedish units where appropriate (g, kg, ml, dl, l, st, förp).
       - quantity and unit are null when not determinable from the receipt.
    Respond with a JSON object only. No prose.
    """

    user = "Extract the store name, total, and grocery items from this receipt."
    {system, user}
  end

  @deals_json_schema %{
    type: "object",
    required: ["deals"],
    additionalProperties: false,
    properties: %{
      deals: %{
        type: "array",
        items: %{
          type: "object",
          required: ["chain", "product_name", "store"],
          additionalProperties: false,
          properties: %{
            chain: %{type: "string"},
            store: %{type: "string"},
            product_name: %{type: "string"},
            brand: %{type: ["string", "null"]},
            size: %{type: ["string", "null"]},
            price: %{type: ["number", "null"]},
            price_unit: %{type: ["string", "null"]},
            offer_condition: %{type: ["string", "null"]},
            regular_price: %{type: ["string", "null"]},
            comparison_price: %{type: ["string", "null"]},
            valid_from: %{type: ["string", "null"]},
            valid_until: %{type: ["string", "null"]}
          }
        }
      }
    }
  }

  def deals_json_schema do
    %{
      type: "json_schema",
      json_schema: %{name: "deals", strict: true, schema: @deals_json_schema}
    }
  end

  def parse_deals_pdf do
    system = """
    You are a grocery deals extractor. Given a PDF flyer or weekly deals catalog from a Swedish supermarket:
    Extract every product deal/offer into the structured format.
    - chain: lowercase chain identifier, one of: "ica", "coop", "lidl", "willys", "hemkop", "citygross", "other"
    - store: the full store name from the PDF (e.g. "ICA Maxi Flemingsberg", "Coop Forum Nacka")
    - product_name: the product name as printed
    - brand: brand name if separate from product name, else null
    - size: package size/weight (e.g. "500g", "1 kg", "6-pack"), null if not stated
    - price: sale price as a number (e.g. 29.90), null if not clear
    - price_unit: currency or unit for price (e.g. "kr", "kr/kg"), null if not stated
    - offer_condition: any condition text (e.g. "3 for 2", "2-pack", "Medlemspris"), null if none
    - regular_price: ordinary price as a number if shown crossed out, else null
    - comparison_price: comparison/unit price string as shown (e.g. "59.80 kr/kg"), null if not shown
    - valid_from / valid_until: ISO 8601 date strings (YYYY-MM-DD) if stated, else null
    Respond with a JSON object only. No prose.
    """

    {system, "Extract all deals from this PDF flyer."}
  end

  @grocery_section_schema %{
    type: "object",
    required: ["section"],
    additionalProperties: false,
    properties: %{
      section: %{
        type: "string",
        enum: ~w(produce meat fish dairy deli frozen bread dry_goods canned beverages herbs_spices condiments household other)
      }
    }
  }

  def grocery_section_schema do
    %{type: "json_schema", json_schema: %{name: "grocery_section", strict: true, schema: @grocery_section_schema}}
  end

  @filter_pantry_schema %{
    type: "object",
    required: ["items"],
    additionalProperties: false,
    properties: %{
      items: %{
        type: "array",
        items: %{
          type: "object",
          required: ["name", "quantity", "unit", "section"],
          additionalProperties: false,
          properties: %{
            name: %{type: "string"},
            quantity: %{type: ["number", "null"]},
            unit: %{type: ["string", "null"]},
            section: %{
              type: "string",
              enum: ~w(produce meat fish dairy deli frozen bread dry_goods canned beverages herbs_spices condiments household other)
            }
          }
        }
      }
    }
  }

  def filter_pantry_schema do
    %{type: "json_schema", json_schema: %{name: "filter_pantry", strict: true, schema: @filter_pantry_schema}}
  end

  def filter_pantry_items(ingredients, pantry) do
    ingredients_text =
      Enum.map_join(ingredients, "\n", fn i ->
        qty = if i.quantity, do: "#{i.quantity} #{i.unit} ", else: ""
        "- #{qty}#{i.name}"
      end)

    pantry_text =
      Enum.map_join(pantry, "\n", fn p ->
        qty = if p.quantity, do: "#{p.quantity} #{p.unit} ", else: ""
        "- #{qty}#{p.name}"
      end)

    system = """
    You are a smart shopping assistant. Given a list of required ingredients and a pantry inventory, return only the items that still need to be bought.
    Rules:
    - If an ingredient is fully covered by the pantry, omit it.
    - If partially covered, include it with the remaining quantity needed.
    - Match items by meaning, not exact string (e.g. "chicken fillet" matches "chicken").
    - Preserve original ingredient names and units in the output.
    - If an ingredient has no quantity, include it unless the pantry clearly has it.
    - Always omit water — it is assumed to be available.
    - For each item, assign a section: produce, meat, fish, dairy, deli, frozen, bread, dry_goods, canned, beverages, herbs_spices, condiments, household, or other.
    Respond with JSON only.
    """

    user = "Ingredients needed:\n#{ingredients_text}\n\nPantry:\n#{pantry_text}"
    {system, user}
  end

  def classify_grocery_item(name) do
    system = """
    You are a grocery store assistant. Classify a grocery item into exactly one store section.
    Sections: produce, meat, fish, dairy, deli, frozen, bread, dry_goods, canned, beverages, herbs_spices, condiments, household, other.
    Respond with JSON only.
    """

    {system, name}
  end

  defp dietary_guidance_instruction(nil), do: ""
  defp dietary_guidance_instruction(""), do: ""

  defp dietary_guidance_instruction(guidance),
    do: "\n- Dietary guidance: #{String.trim(guidance)}"

  defp render(template, assigns) do
    path = Path.join(@prompts_dir, template)
    EEx.eval_file(path, assigns: Map.to_list(assigns))
  end
end
