defmodule Tore.CounterNotes do
  import Ecto.Query
  alias Tore.{Repo, CounterNotes.CounterNote}

  @spec list_for_surface(String.t()) :: [CounterNote.t()]
  def list_for_surface(surface) do
    now = DateTime.utc_now()

    Repo.all(
      from n in CounterNote,
        where:
          n.surface == ^surface and
          n.status == "pending" and
          (is_nil(n.expires_at) or n.expires_at > ^now),
        order_by: [asc: n.inserted_at],
        limit: 3
    )
  end

  @spec create(map()) :: {:ok, CounterNote.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %CounterNote{}
    |> CounterNote.changeset(attrs)
    |> Repo.insert()
  end

  @spec accept(integer()) :: {:ok, CounterNote.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def accept(id) do
    case Repo.get(CounterNote, id) do
      nil -> {:error, :not_found}
      note -> note |> CounterNote.changeset(%{status: "accepted"}) |> Repo.update()
    end
  end

  @spec ignore(integer()) :: {:ok, CounterNote.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def ignore(id) do
    case Repo.get(CounterNote, id) do
      nil -> {:error, :not_found}
      note -> note |> CounterNote.changeset(%{status: "ignored"}) |> Repo.update()
    end
  end

  @spec expire_stale() :: {integer(), nil}
  def expire_stale do
    now = DateTime.utc_now()
    Repo.update_all(
      from(n in CounterNote,
        where: n.status == "pending" and not is_nil(n.expires_at) and n.expires_at <= ^now),
      set: [status: "expired"]
    )
  end
end
