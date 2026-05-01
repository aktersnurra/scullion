defmodule Scullion.Adapters.OpenRouter do
  @behaviour Scullion.LLM

  @impl Scullion.LLM
  def generate_plan(_constraints), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def suggest_recipes(_context), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def extract_recipe_from_html(_html), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def parse_receipt_image(_image), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def parse_deals_image(_image), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def generate_prep_guide(_plan), do: {:error, :not_implemented}
end
