defmodule Tore.Harness.PantryUpdate do
  @moduledoc """
  Pure helpers for `:pantry_belief_update_run` (SPEC §4).

  Three input channels feed this run:

    * `:grocery_checkoff` — grocery list item checked off (Tier 1, auto-apply)
    * `:manual`           — user added/edited an item by hand (Tier 1, auto-apply)
    * `:shelf_photo`      — chat photo classified as `:pantry_items` (Tier 2,
                            editable card if ≥5 items or low confidence)

  All channels normalise to a flat `[%{name, quantity, unit, category, ...}]`
  list, run it through the LLM canonicaliser, then atomically upsert pantry
  beliefs (find-or-create ingredient, find-or-create-or-bump pantry row).
  """

  alias Tore.Harness.Artifact.PantryBeliefUpdate, as: Artifact
  alias Tore.Pantry

  @needs_user_item_threshold 5

  @spec parse_shelf_photo(binary()) :: {:ok, [map()]} | {:error, term()}
  def parse_shelf_photo(image_binary) do
    Pantry.parse_image(image_binary)
  end

  @doc """
  Build the `PantryBeliefUpdate` artifact from raw items + a channel, marking
  each line with the appropriate provenance.
  """
  @spec build_artifact([map()], atom()) :: Artifact.t()
  def build_artifact(items, channel) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    provenance = provenance_for(channel)

    %Artifact{
      items:
        Enum.map(items, fn it ->
          %{
            name: it[:name] || it["name"],
            change: :added,
            quantity: it[:quantity] || it["quantity"],
            unit: it[:unit] || it["unit"],
            category: it[:category] || it["category"],
            provenance: provenance,
            last_seen_at: now
          }
        end)
    }
  end

  defp provenance_for(:grocery_checkoff), do: "grocery_checkoff"
  defp provenance_for(:manual), do: "manual"
  defp provenance_for(:shelf_photo), do: "vision"

  @doc """
  Tier decision per SPEC §A.6.1: vision input always needs user review when
  the parsed batch is non-trivial. Tier 1 channels (manual, grocery
  checkoff) auto-apply.
  """
  @spec needs_user?(atom(), [map()]) :: boolean()
  def needs_user?(:shelf_photo, items), do: length(items) >= @needs_user_item_threshold
  def needs_user?(_, _), do: false

  @doc """
  Canonicalise the artifact items via the LLM, then atomically upsert each
  belief. Returns `{:ok, counts}` where counts is `%{added: n, bumped: n}`.
  """
  @spec apply!(Artifact.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def apply!(%Artifact{items: items}, locale) do
    raws = Enum.map(items, &%{raw_name: &1.name})

    with {:ok, norms} <- Pantry.canonicalise(raws, locale) do
      indexed = Map.new(norms, fn n -> {n.raw_name, n} end)

      Tore.Repo.transaction(fn ->
        Enum.reduce(items, %{added: 0, bumped: 0}, fn it, acc ->
          attrs = merge_norm(it, Map.get(indexed, it.name))

          case Pantry.upsert_belief(attrs) do
            {:ok, _, :added} -> Map.update!(acc, :added, &(&1 + 1))
            {:ok, _, :bumped} -> Map.update!(acc, :bumped, &(&1 + 1))
            {:error, reason} -> Tore.Repo.rollback(reason)
          end
        end)
      end)
    end
  end

  defp merge_norm(it, nil), do: it

  defp merge_norm(it, n) do
    it
    |> Map.put(:catalogue_name, n.catalogue_name || it.name)
    |> Map.put(:matched_key, n.matched_key)
    |> Map.put(:category, it[:category] || n.category)
    |> Map.put(:default_unit, n.default_unit)
  end
end
