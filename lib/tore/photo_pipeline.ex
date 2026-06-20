defmodule Tore.PhotoPipeline do
  @confidence_threshold 0.6

  @type ctx :: %{household_id: integer(), user_id: integer() | nil}

  @spec process_uploads([binary()], ctx()) :: {:ok, list()} | {:error, term()}
  def process_uploads(binaries, ctx) when is_list(binaries) and is_map(ctx) do
    classified =
      binaries
      |> Task.async_stream(&classify_one/1, timeout: 30_000, on_timeout: :kill_task)
      |> Enum.flat_map(fn
        {:ok, {:ok, result}} -> [result]
        _ -> []
      end)

    # Routing model — robust to mixed/abusive uploads:
    #
    #   - :recipe        → grouped together (multi-page recipe is a real case)
    #   - :receipt       → one run per image (two receipts ≠ one combined)
    #   - :pantry_items  → one run per image (two shelves ≠ one shelf)
    #   - :fridge        → one suggestion set per image
    #   - :unknown       → one ambiguous bubble per image
    #
    # This means a single "Send" with three receipts + a fridge photo
    # produces three receipt runs and one fridge result — no silent merging.
    by_class = Enum.group_by(classified, & &1.class)

    recipe_result =
      case Map.get(by_class, :recipe, []) do
        [] -> []
        entries -> [route_group(:recipe, Enum.map(entries, & &1.binary), ctx)]
      end

    per_image_results =
      by_class
      |> Map.drop([:recipe])
      |> Enum.flat_map(fn {class, entries} ->
        Enum.map(entries, fn %{binary: bin} -> route_group(class, [bin], ctx) end)
      end)

    {:ok, recipe_result ++ per_image_results}
  end

  defp classify_one(binary) do
    case classify_image(binary) do
      {:ok, %{class: class, confidence: conf}} when conf >= @confidence_threshold ->
        {:ok, %{class: class, binary: binary}}

      {:ok, _low_confidence} ->
        {:ok, %{class: :unknown, binary: binary}}

      {:error, _} ->
        {:ok, %{class: :unknown, binary: binary}}
    end
  end

  @classifier_system """
  You are an image classifier for a meal planning app.
  Classify the image into exactly one of these categories: receipt, recipe, pantry_items, fridge, unknown.
  - receipt: a store receipt or invoice with line items and prices
  - recipe: a recipe card, cookbook page, or handwritten recipe
  - pantry_items: individual food products, cans, boxes, ingredients on a shelf or counter
  - fridge: an open fridge or freezer showing its contents
  - unknown: anything else
  Return JSON only: {"class": "<one of the five values>", "confidence": <0.0-1.0>}
  """

  defp classify_image(binary) do
    # Classification is a 5-way one-token decision — no need for the heavy
    # OCR vision model. Use the dedicated cheap classifier tier.
    opts = [model: classifier_model()]

    case Tore.LLM.vision([{:image, binary}], @classifier_system, "Classify this image.", opts) do
      {:ok, %{"class" => cls, "confidence" => conf}, _usage} ->
        {:ok, %{class: parse_image_class(cls), confidence: conf}}

      {:ok, _, _} ->
        {:ok, %{class: :unknown, confidence: 0.0}}

      {:error, _} = err ->
        err
    end
  end

  defp classifier_model,
    do: Application.get_env(:tore, :openrouter_classifier_model, "google/gemini-3.1-flash-lite")

  defp parse_image_class("receipt"), do: :receipt
  defp parse_image_class("recipe"), do: :recipe
  defp parse_image_class("pantry_items"), do: :pantry_items
  defp parse_image_class("fridge"), do: :fridge
  defp parse_image_class(_), do: :unknown

  defp route_group(:recipe, images, _ctx) do
    case Tore.Recipes.extract_from_images(images) do
      {:ok, recipe} -> %{class: :recipe, status: :ok, result: recipe}
      {:error, reason} -> %{class: :recipe, status: :error, result: reason}
    end
  end

  # SPEC §5: receipt photo dispatches :receipt_ingestion_run via the harness;
  # the run lands in :needs_user and the UI surfaces an editable card at
  # /runs/:stream_id.
  defp route_group(:receipt, [image | _], ctx) do
    dispatch_ctx = %{
      household_id: ctx.household_id,
      user_id: ctx[:user_id],
      image_binary: image,
      image_path: nil
    }

    case Tore.Harness.Orchestrator.dispatch(:receipt_ingestion_run, dispatch_ctx) do
      {:ok, %Tore.Harness.Run.State.NeedsUser{stream_id: sid}} ->
        %{class: :receipt, status: :needs_review, run_stream_id: sid}

      {:ok, %Tore.Harness.Run.State.Failed{stream_id: sid, failure_code: code}} ->
        %{class: :receipt, status: :error, result: code, run_stream_id: sid}

      {:error, reason} ->
        %{class: :receipt, status: :error, result: reason}
    end
  end

  # SPEC §4: shelf photo dispatches :pantry_belief_update_run via the harness.
  # Tier 2 — if ≥5 items the run lands in :needs_user with an editable card;
  # otherwise auto-applies via canonicalisation + upsert.
  defp route_group(:pantry_items, [image | _], ctx) do
    dispatch_ctx = %{
      household_id: ctx.household_id,
      user_id: ctx[:user_id],
      channel: :shelf_photo,
      image_binary: image
    }

    case Tore.Harness.Orchestrator.dispatch(:pantry_belief_update_run, dispatch_ctx) do
      {:ok, %Tore.Harness.Run.State.NeedsUser{stream_id: sid}} ->
        %{class: :pantry_items, status: :needs_review, run_stream_id: sid}

      {:ok, %Tore.Harness.Run.State.Applied{}} ->
        %{class: :pantry_items, status: :ok, result: :applied}

      {:ok, %Tore.Harness.Run.State.Failed{failure_code: code}} ->
        %{class: :pantry_items, status: :error, result: code}

      {:error, reason} ->
        %{class: :pantry_items, status: :error, result: reason}
    end
  end

  defp route_group(:fridge, [image | _], _ctx) do
    case Tore.Pantry.parse_image(image) do
      {:ok, items} -> %{class: :fridge, status: :ok, result: items}
      {:error, reason} -> %{class: :fridge, status: :error, result: reason}
    end
  end

  defp route_group(:unknown, _images, _ctx) do
    %{class: :unknown, status: :ambiguous, result: nil}
  end
end
