defmodule Scullion.ImageGen do
  @callback generate_food_image(title :: String.t(), recipe_text :: String.t() | nil) ::
              {:ok, binary()} | {:error, term()}
end
