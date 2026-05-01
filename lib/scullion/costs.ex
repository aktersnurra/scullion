defmodule Scullion.Costs do
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
