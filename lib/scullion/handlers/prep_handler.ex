defmodule Scullion.Handlers.PrepHandler do
  @llm Application.compile_env(:scullion, :llm_client)

  def generate_guide(week_start) do
    with {:ok, guide} <- @llm.generate_prep_guide(%{week_start: week_start}) do
      Scullion.Prep.save_guide(Map.put(guide, :week_start, week_start))
    end
  end
end
