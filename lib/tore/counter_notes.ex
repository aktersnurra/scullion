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
        where: n.status == "pending" and not is_nil(n.expires_at) and n.expires_at <= ^now
      ),
      set: [status: "expired"]
    )
  end

  @scan_kinds ~w(swap_suggestion freezer_fallback missing_ingredient usual_item_missing)

  @doc "One scan owns the scan-kind notes: expire the previous pending batch, insert the new one."
  def replace_scan_notes(attrs_list) do
    Repo.transaction(fn ->
      from(n in CounterNote, where: n.status == "pending" and n.kind in @scan_kinds)
      |> Repo.update_all(set: [status: "expired"])

      Enum.map(attrs_list, fn attrs ->
        case create(attrs) do
          {:ok, note} -> note
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc "Dismissal is signal: what the household recently swiped away, for the next scan prompt."
  def recently_ignored(days) do
    since = DateTime.add(DateTime.utc_now(), -days, :day)

    from(n in CounterNote,
      where: n.status == "ignored" and n.inserted_at >= ^since,
      select: %{kind: n.kind, title: n.title}
    )
    |> Repo.all()
  end

  @doc """
  Accept the note and execute its proposed run. Deterministic proposals
  (add_item) apply directly — code disposes; planner commands dispatch a
  scoped run with counter_note_followup provenance.
  """
  @spec follow_up(integer(), %{household_id: term(), user_id: term()}) ::
          {:ok, term()} | {:error, term()}
  def follow_up(id, %{household_id: household_id, user_id: user_id}) do
    note = Repo.get!(CounterNote, id)

    case note.proposed_run do
      %{"kind" => "add_item", "name" => name} = pr ->
        {:ok, _} = accept(id)

        week_start = week_start(Date.utc_today())
        list_id = "shop_list:#{Date.to_iso8601(week_start)}"

        Tore.Shop.add_item(list_id, name, pr["quantity"], pr["unit"], user_id)

      %{"kind" => "planner_command", "command" => command} = pr ->
        {:ok, _} = accept(id)

        week_start = week_start(Date.utc_today())

        Tore.Harness.Orchestrator.dispatch(:planner_command_run, %{
          household_id: household_id,
          user_id: user_id,
          command: command,
          plan_stream_id: "plan:#{Date.to_iso8601(week_start)}",
          week_start: week_start,
          scoped_slot: pr["scoped_slot"],
          started_by: "counter_note_followup"
        })

      _ ->
        {:error, :no_proposed_run}
    end
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end
end
