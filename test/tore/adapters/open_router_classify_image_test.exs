defmodule Tore.Adapters.OpenRouterClassifyImageTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "classify_image mock returns recipe class" do
    Tore.MockLLM
    |> expect(:classify_image, fn _binary ->
      {:ok, %{class: :recipe, confidence: 0.9}}
    end)

    assert {:ok, %{class: :recipe, confidence: 0.9}} =
             Tore.MockLLM.classify_image(<<"fake_image_binary">>)
  end

  test "classify_image mock returns unknown for low-confidence result" do
    Tore.MockLLM
    |> expect(:classify_image, fn _binary ->
      {:ok, %{class: :unknown, confidence: 0.4}}
    end)

    assert {:ok, %{class: :unknown, confidence: conf}} =
             Tore.MockLLM.classify_image(<<"fake_image_binary">>)

    assert conf < 0.6
  end
end
