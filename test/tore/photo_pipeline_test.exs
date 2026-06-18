defmodule Tore.PhotoPipelineTest do
  use ExUnit.Case, async: false
  import Mox

  setup :verify_on_exit!

  test "low-confidence image returns ambiguous group" do
    Tore.MockLLM
    |> expect(:classify_image, fn _binary ->
      {:ok, %{class: :receipt, confidence: 0.4}}
    end)

    assert {:ok, [%{class: :unknown, status: :ambiguous}]} =
             Tore.PhotoPipeline.process_uploads([<<"blurry">>], %{household_id: 1, user_id: nil})
  end

  test "process_uploads classifies recipe image" do
    Tore.MockLLM
    |> expect(:classify_image, fn _binary ->
      {:ok, %{class: :recipe, confidence: 0.95}}
    end)
    |> expect(:parse_recipe_images, fn _images, _locale ->
      {:ok, %{"title" => "Pasta", "ingredients" => [], "instructions" => "Cook it"}}
    end)

    assert {:ok, [%{class: :recipe, status: :ok}]} =
             Tore.PhotoPipeline.process_uploads([<<"recipe_img">>], %{household_id: 1, user_id: nil})
  end
end
