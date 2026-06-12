defmodule Tore.PhotoPipeline do
  @llm Application.compile_env(:tore, :llm_client)

  @confidence_threshold 0.6

  @spec process_uploads([binary()], String.t()) :: {:ok, list()} | {:error, term()}
  def process_uploads(binaries, _correlation_id) when is_list(binaries) do
    classified =
      binaries
      |> Task.async_stream(&classify_one/1, timeout: 30_000, on_timeout: :kill_task)
      |> Enum.flat_map(fn
        {:ok, {:ok, result}} -> [result]
        _ -> []
      end)

    results =
      classified
      |> Enum.group_by(& &1.class)
      |> Enum.map(fn {class, entries} ->
        images = Enum.map(entries, & &1.binary)
        route_group(class, images)
      end)

    {:ok, results}
  end

  defp classify_one(binary) do
    case @llm.classify_image(binary) do
      {:ok, %{class: class, confidence: conf}} when conf >= @confidence_threshold ->
        {:ok, %{class: class, binary: binary}}

      {:ok, _low_confidence} ->
        {:ok, %{class: :unknown, binary: binary}}

      {:error, _} ->
        {:ok, %{class: :unknown, binary: binary}}
    end
  end

  defp route_group(:recipe, images) do
    case Tore.Recipes.extract_from_images(images) do
      {:ok, recipe} -> %{class: :recipe, status: :ok, result: recipe}
      {:error, reason} -> %{class: :recipe, status: :error, result: reason}
    end
  end

  defp route_group(:receipt, [image | _]) do
    case Tore.Costs.parse_receipt_image(image) do
      {:ok, parsed} -> %{class: :receipt, status: :ok, result: parsed}
      {:ok, parsed, _usage} -> %{class: :receipt, status: :ok, result: parsed}
      {:error, reason} -> %{class: :receipt, status: :error, result: reason}
    end
  end

  defp route_group(:pantry_items, [image | _]) do
    case Tore.Pantry.parse_image(image) do
      {:ok, items} -> %{class: :pantry_items, status: :ok, result: items}
      {:ok, items, _usage} -> %{class: :pantry_items, status: :ok, result: items}
      {:error, reason} -> %{class: :pantry_items, status: :error, result: reason}
    end
  end

  defp route_group(:fridge, [image | _]) do
    case Tore.Pantry.parse_image(image) do
      {:ok, items} -> %{class: :fridge, status: :ok, result: items}
      {:ok, items, _usage} -> %{class: :fridge, status: :ok, result: items}
      {:error, reason} -> %{class: :fridge, status: :error, result: reason}
    end
  end

  defp route_group(:unknown, _images) do
    %{class: :unknown, status: :ambiguous, result: nil}
  end
end
