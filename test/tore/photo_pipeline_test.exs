defmodule Tore.PhotoPipelineTest do
  use ExUnit.Case, async: false
  import Mox

  setup :verify_on_exit!

  test "low-confidence image returns ambiguous group" do
    Tore.MockLLM
    |> expect(:vision, fn _blobs, _system, _user, _opts ->
      {:ok, %{"class" => "receipt", "confidence" => 0.4}, %{}}
    end)

    assert {:ok, [%{class: :unknown, status: :ambiguous}]} =
             Tore.PhotoPipeline.process_uploads([<<"blurry">>], %{household_id: 1, user_id: nil})
  end

  test "process_uploads classifies recipe image" do
    Tore.MockLLM
    # 1st vision call: classify_image
    |> expect(:vision, fn _blobs, _system, _user, _opts ->
      {:ok, %{"class" => "recipe", "confidence" => 0.95}, %{}}
    end)
    # 2nd vision call: extract_from_images (returns the raw recipe schema map
    # that Recipes.recipe_attrs_from_raw shapes downstream)
    |> expect(:vision, fn _blobs, _system, _user, _opts ->
      {:ok,
       %{
         "title" => "Pasta",
         "description" => nil,
         "ingredients" => [],
         "steps" => [],
         "tags" => []
       }, %{}}
    end)

    assert {:ok, [%{class: :recipe, status: :ok}]} =
             Tore.PhotoPipeline.process_uploads([<<"recipe_img">>], %{
               household_id: 1,
               user_id: nil
             })
  end
end
