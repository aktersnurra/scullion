defmodule Scullion.Prep do
  @spec save_guide(map()) :: {:ok, term()} | {:error, term()}
  def save_guide(_attrs), do: {:error, :not_implemented}

  @spec get_guide_for_week(Date.t()) :: {:ok, term()} | {:error, :not_found}
  def get_guide_for_week(_week_start), do: {:error, :not_found}
end
