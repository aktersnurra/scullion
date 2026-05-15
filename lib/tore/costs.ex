defmodule Tore.Costs do
  alias Tore.{Repo, Costs.LLMUsage, Costs.Receipt, Costs.LineItem, Costs.DiningOut}
  import Ecto.Query

  def log_llm_usage(attrs) do
    %LLMUsage{} |> LLMUsage.changeset(attrs) |> Repo.insert()
  end

  def llm_spend_this_month do
    month_start = Date.beginning_of_month(Date.utc_today())
    threshold = NaiveDateTime.new!(month_start, ~T[00:00:00])

    Repo.one(
      from u in LLMUsage,
        where: u.inserted_at >= ^threshold,
        select: coalesce(sum(u.cost_usd), 0.0)
    )
  end

  def last_llm_call(feature) do
    Repo.one(
      from u in LLMUsage,
        where: u.feature == ^to_string(feature),
        order_by: [desc: u.inserted_at],
        limit: 1
    )
  end

  @spec list_receipts() :: [Receipt.t()]
  def list_receipts do
    Repo.all(from r in Receipt, order_by: [desc: r.date], limit: 50)
  end

  @spec log_receipt(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def log_receipt(attrs) do
    line_items = Map.get(attrs, :line_items, [])
    attrs = Map.delete(attrs, :line_items)

    Repo.transaction(fn ->
      case %Receipt{} |> Receipt.changeset(attrs) |> Repo.insert() do
        {:ok, receipt} ->
          Enum.each(line_items, fn item ->
            %LineItem{}
            |> LineItem.changeset(Map.put(item, :receipt_id, receipt.id))
            |> Repo.insert!()
          end)

          receipt

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @spec log_dining_out(map()) :: {:ok, DiningOut.t()} | {:error, term()}
  def log_dining_out(attrs) do
    %DiningOut{} |> DiningOut.changeset(attrs) |> Repo.insert()
  end

  @spec weekly_summary(Date.t()) :: {:ok, map()}
  def weekly_summary(week_start) do
    week_end = Date.add(week_start, 6)

    grocery =
      Repo.one(
        from r in Receipt,
          where: r.date >= ^week_start and r.date <= ^week_end,
          select: coalesce(sum(r.total_amount), 0)
      ) |> to_decimal()

    dining =
      Repo.one(
        from d in DiningOut,
          where: d.date >= ^week_start and d.date <= ^week_end,
          select: coalesce(sum(d.total_amount), 0)
      ) |> to_decimal()

    {:ok, %{grocery_total: grocery, dining_total: dining, total: Decimal.add(grocery, dining)}}
  end

  @spec monthly_summary(integer(), integer()) :: {:ok, map()}
  def monthly_summary(year, month) do
    {:ok, month_start} = Date.new(year, month, 1)
    month_end = Date.end_of_month(month_start)

    grocery =
      Repo.one(
        from r in Receipt,
          where: r.date >= ^month_start and r.date <= ^month_end,
          select: coalesce(sum(r.total_amount), 0)
      ) |> to_decimal()

    receipt_count =
      Repo.one(
        from r in Receipt,
          where: r.date >= ^month_start and r.date <= ^month_end,
          select: count(r.id)
      )

    dining =
      Repo.one(
        from d in DiningOut,
          where: d.date >= ^month_start and d.date <= ^month_end,
          select: coalesce(sum(d.total_amount), 0)
      ) |> to_decimal()

    dining_count =
      Repo.one(
        from d in DiningOut,
          where: d.date >= ^month_start and d.date <= ^month_end,
          select: count(d.id)
      )

    {:ok,
     %{
       grocery_total: grocery,
       dining_total: dining,
       total: Decimal.add(grocery, dining),
       receipt_count: receipt_count,
       dining_count: dining_count
     }}
  end

  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)

  @spec cost_per_meal(map()) :: {:ok, Decimal.t()} | {:error, term()}
  def cost_per_meal(%{week_start: week_start, meal_count: meal_count}) when meal_count > 0 do
    {:ok, %{grocery_total: total}} = weekly_summary(week_start)
    {:ok, Decimal.div(total, meal_count)}
  end

  def cost_per_meal(_), do: {:error, :invalid_period}
end
