defmodule Tore.Handlers.PantryHandler do
  @llm Application.compile_env(:tore, :llm_client)

  def parse_image(image_binary) do
    @llm.parse_pantry_image(image_binary)
  end

  def confirm_items(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case Tore.Pantry.add_item(item) do
        {:ok, pantry_item} -> {:cont, {:ok, [pantry_item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      error -> error
    end
  end
end
