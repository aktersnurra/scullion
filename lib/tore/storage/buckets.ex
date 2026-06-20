defmodule Tore.Storage.Buckets do
  @moduledoc """
  Centralised S3 bucket names.

  * `recipes/` — long-lived recipe imagery (lives as long as the recipe).
  * `runs/`    — short-lived photos attached to a `KitchenRun` (e.g. uploaded
                 receipts, shelf photos). Deleted when the run terminates
                 (commit / discard / TTL-sweep).
  """

  @recipes "tore-recipes"
  @runs "tore-runs"

  def recipes, do: @recipes
  def runs, do: @runs

  def all, do: [@recipes, @runs]
end
