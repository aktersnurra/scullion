defmodule Tore.HouseholdInsightsTest do
  use Tore.DataCase, async: false

  alias Tore.Household

  defp insight_attrs(overrides \\ %{}) do
    Map.merge(%{kind: "skip_pattern", body: "Household skips Mondays", confidence: 0.8}, overrides)
  end

  test "list_active_insights returns only active insights sorted by confidence desc" do
    {:ok, _} = Household.replace_insights([insight_attrs(%{confidence: 0.6})])
    {:ok, _} = Household.replace_insights([
      insight_attrs(%{confidence: 0.9, body: "High confidence"}),
      insight_attrs(%{confidence: 0.4, body: "Low confidence"})
    ])

    active = Household.list_active_insights()
    assert length(active) == 2
    assert hd(active).confidence == 0.9
    assert Enum.all?(active, &(&1.status == "active"))
  end

  test "replace_insights supersedes previous active insights" do
    {:ok, first_batch} = Household.replace_insights([insight_attrs()])
    first_id = hd(first_batch).id

    {:ok, _} = Household.replace_insights([insight_attrs(%{body: "New insight"})])

    old = Tore.Repo.get!(Tore.Household.HouseholdInsight, first_id)
    assert old.status == "superseded"
  end

  test "dismiss_insight marks insight as dismissed" do
    {:ok, [insight]} = Household.replace_insights([insight_attrs()])

    {:ok, dismissed} = Household.dismiss_insight(insight.id)
    assert dismissed.status == "dismissed"
    assert Household.list_active_insights() == []
  end

  test "list_active_insights excludes dismissed insights" do
    {:ok, [insight]} = Household.replace_insights([insight_attrs()])
    Household.dismiss_insight(insight.id)

    assert Household.list_active_insights() == []
  end
end
