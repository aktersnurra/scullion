defmodule Tore.Storage.Buckets do
  @recipes "tore-recipes"
  @receipts "tore-receipts"
  @uploads "tore-uploads"

  def recipes, do: @recipes
  def receipts, do: @receipts
  def uploads, do: @uploads

  def all, do: [@recipes, @receipts, @uploads]
end
