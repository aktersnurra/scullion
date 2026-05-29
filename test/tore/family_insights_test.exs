defmodule Tore.FamilyInsightsTest do
  use Tore.DataCase, async: false

  alias Tore.Family

  defp insight_attrs(overrides \\ %{}) do
    Map.merge(%{kind: "skip_pattern", body: "Family skips Mondays", confidence: 0.8}, overrides)
  end

  test "list_active_insights returns only active insights sorted by confidence desc" do
    {:ok, _} = Family.replace_insights([insight_attrs(%{confidence: 0.6})])
    {:ok, _} = Family.replace_insights([
      insight_attrs(%{confidence: 0.9, body: "High confidence"}),
      insight_attrs(%{confidence: 0.4, body: "Low confidence"})
    ])

    active = Family.list_active_insights()
    assert length(active) == 2
    assert hd(active).confidence == 0.9
    assert Enum.all?(active, &(&1.status == "active"))
  end

  test "replace_insights supersedes previous active insights" do
    {:ok, first_batch} = Family.replace_insights([insight_attrs()])
    first_id = hd(first_batch).id

    {:ok, _} = Family.replace_insights([insight_attrs(%{body: "New insight"})])

    old = Tore.Repo.get!(Tore.Family.FamilyInsight, first_id)
    assert old.status == "superseded"
  end

  test "dismiss_insight marks insight as dismissed" do
    {:ok, [insight]} = Family.replace_insights([insight_attrs()])

    {:ok, dismissed} = Family.dismiss_insight(insight.id)
    assert dismissed.status == "dismissed"
    assert Family.list_active_insights() == []
  end

  test "list_active_insights excludes dismissed insights" do
    {:ok, [insight]} = Family.replace_insights([insight_attrs()])
    Family.dismiss_insight(insight.id)

    assert Family.list_active_insights() == []
  end
end
