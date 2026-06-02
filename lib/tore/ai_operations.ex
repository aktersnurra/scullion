defmodule Tore.AiOperations do
  alias Tore.{Repo, AiOperations.AiOperation}
  import Ecto.Query

  @spec log(map()) :: {:ok, AiOperation.t()} | {:error, Ecto.Changeset.t()}
  def log(attrs) do
    %AiOperation{}
    |> AiOperation.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_for_run(String.t()) :: [AiOperation.t()]
  def list_for_run(run_stream_id) do
    Repo.all(
      from o in AiOperation,
        where: o.run_stream_id == ^run_stream_id,
        order_by: [asc: o.step_index]
    )
  end
end
