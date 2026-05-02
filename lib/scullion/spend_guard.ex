defmodule Scullion.SpendGuard do
  @monthly_limit_usd 20.0
  @cooldown_seconds 60
  # rough haiku pricing, used only for pre-call estimate
  @price_per_token 4.176 / 1_000_000

  def allow?(feature, estimated_tokens \\ 50_000) do
    with :ok <- budget_ok?(estimated_tokens),
         :ok <- cooldown_ok?(feature) do
      :ok
    end
  end

  def log_usage(feature, usage) do
    Scullion.Costs.log_llm_usage(%{
      feature: to_string(feature),
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      cost_usd: usage.cost_usd
    })

    :ok
  end

  defp budget_ok?(estimated_tokens) do
    spent = Scullion.Costs.llm_spend_this_month()
    if spent + estimated_tokens * @price_per_token > @monthly_limit_usd do
      {:error, :budget_exceeded}
    else
      :ok
    end
  end

  defp cooldown_ok?(feature) do
    case Scullion.Costs.last_llm_call(feature) do
      nil ->
        :ok

      last ->
        seconds = DateTime.diff(DateTime.utc_now(), DateTime.from_naive!(last.inserted_at, "Etc/UTC"))
        if seconds < @cooldown_seconds, do: {:error, :cooldown}, else: :ok
    end
  end
end
