defmodule Tore.Harness.ReceiptIngestion do
  @moduledoc """
  Pure helpers for `:receipt_ingestion_run` (SPEC §5).

  The Orchestrator drives the Run aggregate; this module owns parsing the
  receipt image, shaping `CostEntry` + `PantryBeliefUpdate` artifacts, and
  the atomic apply on commit (Costs + Pantry in one transaction).
  """

  alias Tore.Harness.Artifact.{CostEntry, PantryBeliefUpdate}
  alias Tore.{Costs, Pantry, Repo}

  @llm Application.compile_env(:tore, :llm_client)

  @spec parse(binary()) ::
          {:ok, %{store_name: String.t() | nil, total: Decimal.t() | nil, items: [map()]}}
          | {:error, term()}
  def parse(image_binary) do
    case @llm.parse_receipt_for_pantry(image_binary) do
      {:ok, parsed, _usage} -> {:ok, parsed}
      {:error, _} = err -> err
    end
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
  Atomically commit both artifacts: Costs.log_receipt + Pantry add_item per
  line. Either both land or neither does. Returns {:ok, receipt} on success.
  """
  @spec apply!(CostEntry.t(), PantryBeliefUpdate.t(), integer() | nil) ::
          {:ok, Costs.Receipt.t()} | {:error, term()}
  def apply!(%CostEntry{} = cost, %PantryBeliefUpdate{} = pantry, user_id) do
    Repo.transaction(fn ->
      with {:ok, receipt} <- log_receipt(cost, user_id),
           :ok <- add_pantry(pantry) do
        receipt
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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

  defp to_cost_line_item(it) do
    %{
      product_name: it.name,
      quantity: it[:quantity],
      total_price: it[:total_price],
      category: it[:category]
    }
  end

  defp add_pantry(%PantryBeliefUpdate{items: items}) do
    Enum.reduce_while(items, :ok, fn it, :ok ->
      attrs = %{
        name: it.name,
        quantity: it[:quantity],
        unit: it[:unit],
        category: it[:category],
        provenance: it.provenance,
        last_seen_at: it.last_seen_at
      }

      case Pantry.add_item(attrs) do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end
end
