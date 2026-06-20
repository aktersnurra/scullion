defmodule Tore.Harness.ReceiptIngestion do
  @moduledoc """
  Pure helpers for `:receipt_ingestion_run` (SPEC §5).

  The Orchestrator drives the Run aggregate; this module owns parsing the
  receipt image, shaping `CostEntry` + `PantryBeliefUpdate` artifacts, and
  the atomic apply on commit (Costs + Pantry in one transaction).
  """

  alias Tore.Harness.Artifact.{CostEntry, PantryBeliefUpdate}
  alias Tore.{Costs, Pantry, Repo}

  @spec parse(binary(), String.t() | nil) ::
          {:ok, %{store_name: String.t() | nil, total: Decimal.t() | nil, items: [map()]}}
          | {:error, term()}
  def parse(image_binary, locale \\ nil) do
    Tore.Costs.parse_receipt_for_pantry(image_binary, locale)
  end

  @spec build_artifacts(map(), keyword()) :: {CostEntry.t(), PantryBeliefUpdate.t()}
  def build_artifacts(parsed, opts \\ []) do
    date = Keyword.get(opts, :date, Date.utc_today())
    image_path = Keyword.get(opts, :image_path)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    items = parsed.items || []

    cost = %CostEntry{
      store_name: parsed.store_name || "",
      date: date,
      total: parsed.total || Decimal.new(0),
      line_items:
        Enum.map(items, fn it ->
          %{
            name: it.name,
            quantity: it[:quantity],
            unit: it[:unit],
            total_price: it[:total_price],
            category: it[:category]
          }
        end),
      image_path: image_path
    }

    pantry = %PantryBeliefUpdate{
      items:
        Enum.map(items, fn it ->
          %{
            name: it.name,
            change: :added,
            quantity: it[:quantity],
            unit: it[:unit],
            category: it[:category],
            provenance: "receipt",
            last_seen_at: now
          }
        end)
    }

    {cost, pantry}
  end

  @doc """
  Atomically commit both artifacts: Costs.log_receipt + canonicalised
  Pantry upsert per line. Either both land or neither does. Returns
  `{:ok, receipt}` on success.

  Canonicalisation runs the raw/edited names through the LLM (locale-aware)
  before the upsert, so repeated buys collapse into one pantry row per
  ingredient and `KYCKLINGLA FILE` / `Kycklinglår filé` / `kycklinglårfile`
  all dedupe.
  """
  @spec apply!(CostEntry.t(), PantryBeliefUpdate.t(), integer() | nil, String.t() | nil) ::
          {:ok, Costs.Receipt.t()} | {:error, term()}
  def apply!(%CostEntry{} = cost, %PantryBeliefUpdate{} = pantry, user_id, locale \\ nil) do
    with {:ok, canonicalised} <- canonicalise(pantry, locale) do
      Repo.transaction(fn ->
        with {:ok, receipt} <- log_receipt(cost, user_id),
             :ok <- upsert_pantry(canonicalised) do
          receipt
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  # Run the pantry items through the LLM canonicaliser, then merge the
  # canonicalised display name + matched key + category + default_unit back
  # onto each original item map.
  defp canonicalise(%PantryBeliefUpdate{items: items}, locale) do
    raws = Enum.map(items, &%{raw_name: &1.name})

    with {:ok, norms} <- Pantry.canonicalise(raws, locale) do
      indexed = Map.new(norms, fn n -> {n.raw_name, n} end)

      merged =
        Enum.map(items, fn it ->
          case Map.get(indexed, it.name) do
            nil ->
              it

            n ->
              it
              |> Map.put(:catalogue_name, n.catalogue_name || it.name)
              |> Map.put(:matched_key, n.matched_key)
              |> Map.put(:category, it[:category] || n.category)
              |> Map.put(:default_unit, n.default_unit)
          end
        end)

      {:ok, merged}
    end
  end

  defp log_receipt(%CostEntry{} = cost, user_id) do
    Costs.log_receipt(%{
      date: cost.date,
      store_name: cost.store_name,
      total_amount: cost.total,
      user_id: user_id,
      image_path: cost.image_path,
      line_items: Enum.map(cost.line_items, &to_cost_line_item/1)
    })
  end

  @cost_categories ~w[dairy meat produce frozen dry_goods canned herbs_spices condiments other]

  defp to_cost_line_item(it) do
    %{
      product_name: it.name,
      quantity: it[:quantity],
      total_price: it[:total_price],
      category: sanitise_category(it[:category])
    }
  end

  # Defensive: if the LLM returns a category outside our enum (locale label,
  # made-up string, etc.) fall back to "other" rather than dropping it or
  # crashing the changeset — "other" is what the enum exists for.
  defp sanitise_category(c) when c in @cost_categories, do: c
  defp sanitise_category(_), do: "other"

  defp upsert_pantry(items) do
    Enum.reduce_while(items, :ok, fn it, :ok ->
      case Pantry.upsert_belief(it) do
        {:ok, _item, _change} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
