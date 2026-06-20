defmodule Tore.ImageGen do
  @moduledoc """
  Transport behaviour for image generation. Takes a finished prompt and
  returns image bytes. Prompt construction lives elsewhere (see
  `Tore.Recipes.generate_image/2` and `Tore.LLM.Prompts.write_image_prompt/2`).
  """

  @callback generate_food_image(prompt :: String.t()) ::
              {:ok, binary()} | {:error, term()}
end
