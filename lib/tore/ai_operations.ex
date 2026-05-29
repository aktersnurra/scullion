defmodule Tore.AiOperations do
  alias Tore.{Repo, AiOperations.AiOperation}
  import Ecto.Query

  @spec log(map()) :: {:ok, AiOperation.t()} | {:error, Ecto.Changeset.t()}
  def log(attrs) do
    %AiOperation{}
    |> AiOperation.changeset(attrs)
    |> Repo.insert()
  end

  @spec find_by_correlation(String.t()) :: AiOperation.t() | nil
  def find_by_correlation(correlation_id) do
    Repo.one(from o in AiOperation, where: o.correlation_id == ^correlation_id)
  end
end
