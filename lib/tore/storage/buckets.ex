defmodule Tore.Storage.Buckets do
  @recipes "tore-recipes"

  def recipes, do: @recipes

  def all, do: [@recipes]
end
