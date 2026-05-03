defmodule Scullion.LLM do
  @callback generate_plan(constraints :: map()) :: {:ok, map(), map()} | {:error, term()}
  @callback suggest_recipes(context :: map()) :: {:ok, [map()], map()} | {:error, term()}
  @callback extract_recipe_from_html(html :: String.t()) :: {:ok, map(), map()} | {:error, term()}
  @callback parse_receipt_image(image :: binary()) :: {:ok, [map()], map()} | {:error, term()}
  @callback parse_deals_image(image :: binary()) :: {:ok, [map()], map()} | {:error, term()}
  @callback generate_prep_guide(plan :: map()) :: {:ok, map(), map()} | {:error, term()}
  @callback estimate_nutrition(recipe :: map()) :: {:ok, map(), map()} | {:error, term()}
end
