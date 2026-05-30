defmodule Tore.LLM do
  @callback generate_plan(constraints :: map()) :: {:ok, map(), map()} | {:error, term()}
  @callback suggest_recipes(context :: map()) :: {:ok, [map()], map()} | {:error, term()}
  @callback suggest_slot_recipe(context :: map()) :: {:ok, map(), map()} | {:error, term()}
  @callback extract_recipe_from_html(html :: String.t(), locale :: String.t() | nil) ::
              {:ok, map(), map()} | {:error, term()}
  @callback parse_receipt_image(image :: binary()) :: {:ok, [map()], map()} | {:error, term()}
  @callback parse_deals_image(image :: binary()) :: {:ok, [map()], map()} | {:error, term()}
  @callback parse_deals_pdf(pdf :: binary()) :: {:ok, [map()]} | {:error, term()}
  @callback parse_recipe_images(images :: [binary()], locale :: String.t() | nil) ::
              {:ok, map()} | {:error, term()}
  @callback generate_prep_guide(plan :: map(), locale :: String.t() | nil) ::
              {:ok, map(), map()} | {:error, term()}
  @callback estimate_nutrition(recipe :: map()) :: {:ok, map(), map()} | {:error, term()}
  @callback parse_pantry_image(image :: binary()) :: {:ok, [map()], map()} | {:error, term()}
  @callback parse_receipt_for_pantry(image :: binary()) ::
              {:ok, %{total: Decimal.t() | nil, store_name: String.t() | nil, items: [map()]},
               map()}
              | {:error, term()}

  @callback classify_grocery_item(name :: String.t()) :: {:ok, atom()} | {:error, term()}

  @callback filter_pantry_items(ingredients :: [map()], pantry :: [map()]) ::
              {:ok, [map()]} | {:error, term()}

  @callback suggest_substitution(missing :: String.t(), recipe_context :: String.t()) ::
              {:ok, %{suggestion: String.t(), updated_steps: String.t() | nil}} | {:error, term()}

  @callback cook_mode_steps(recipe :: map()) ::
              {:ok, %{do_first: [String.t()], while_cooking: [String.t()], finish: [String.t()]}} |
              {:error, term()}

  @callback chat(system :: String.t(), messages :: [map()]) ::
              {:ok, String.t(), map()} | {:error, term()}

  @callback classify_image(image :: binary()) ::
              {:ok, %{class: :receipt | :recipe | :pantry_items | :fridge | :unknown, confidence: float()}}
              | {:error, term()}

  @callback synthesise_insights(events_summary :: String.t()) ::
    {:ok, [%{kind: String.t(), body: String.t(), confidence: float(), evidence: [integer()]}]} |
    {:error, term()}

  @type tool_call :: %{id: String.t(), name: String.t(), args: map()}
  @type tool_response ::
          {:message, String.t()}
          | {:tool_calls, [tool_call()]}

  @callback chat_with_tools(
              system :: String.t(),
              messages :: [map()],
              tools :: [map()],
              opts :: keyword()
            ) :: {:ok, tool_response(), usage :: map()} | {:error, term()}
end
