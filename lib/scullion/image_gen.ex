defmodule Scullion.ImageGen do
  @callback generate_food_image(title :: String.t(), ingredients :: [String.t()]) ::
              {:ok, binary()} | {:error, term()}
end
