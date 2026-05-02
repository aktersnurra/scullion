defmodule Scullion.Costs do
  alias Scullion.{Repo, Costs.LLMUsage}
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

  @spec log_receipt(map()) :: {:ok, term()} | {:error, term()}
  def log_receipt(_attrs), do: {:error, :not_implemented}

  @spec log_dining_out(map()) :: {:ok, term()} | {:error, term()}
  def log_dining_out(_attrs), do: {:error, :not_implemented}

  @spec weekly_summary(Date.t()) :: {:ok, map()} | {:error, term()}
  def weekly_summary(_week_start), do: {:error, :not_implemented}

  @spec monthly_summary(integer(), integer()) :: {:ok, map()} | {:error, term()}
  def monthly_summary(_year, _month), do: {:error, :not_implemented}

  @spec cost_per_meal(map()) :: {:ok, map()} | {:error, term()}
  def cost_per_meal(_period), do: {:error, :not_implemented}
end
