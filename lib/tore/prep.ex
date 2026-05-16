defmodule Tore.Prep do
  alias Tore.{Repo, Prep.PrepGuide}
  import Ecto.Query

  def save_guide(attrs) do
    %PrepGuide{}
    |> PrepGuide.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:timeline, :cascade_map, :storage_notes, :daily_assembly, :prep_session, :instructions]},
      conflict_target: [:week_start]
    )
  end

  def get_guide_for_week(week_start) do
    Repo.one(from g in PrepGuide, where: g.week_start == ^week_start)
  end
end
