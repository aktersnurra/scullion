defmodule ToreWeb.HomeLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Tore.Accounts
  alias Tore.Harness.Run
  alias Tore.Harness.Run.{Commands, State}

  setup do
    {:ok, {user, _code}} = Accounts.create_admin("Gustaf")
    conn = build_conn() |> Plug.Test.init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  defp open_needs_user_run(household_id, user_id) do
    sid = Run.next_stream_id()

    {:ok, [opened]} =
      Run.decide(
        %Commands.Open{
          household_id: household_id,
          kind: "receipt_ingestion_run",
          surface: :plan,
          started_by: "user",
          user_id: user_id,
          input: %{}
        },
        %State.Draft{stream_id: sid}
      )

    running = Run.evolve(%State.Draft{stream_id: sid}, opened)

    {:ok, [raised]} =
      Run.decide(%Commands.RaiseQuestion{question: "Which store is this receipt from?"}, running)

    :ok = Run.append(sid, [opened, raised], %{household_id: household_id})
    sid
  end

  test "mounts without crash and shows tonight section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Ikväll"
  end

  test "shows nothing planned when no recipe assigned", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Inget planerat ikväll"
  end

  test "today does not render the week strip", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    refute html =~ "Föregående vecka"
  end

  test "renders the command pill linking to capture", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    bottom_nav_html = view |> element(~s(nav[data-role="bottom-nav"])) |> render()
    assert bottom_nav_html =~ ~s(data-role="command-pill")
    assert bottom_nav_html =~ "/capture"
    assert bottom_nav_html =~ "return_to=%2F"
    refute bottom_nav_html =~ "Fråga Tore"
  end

  describe "app shell nav" do
    test "shows only Today, Plan, Shop as destinations", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      nav_html = view |> element("header nav") |> render()
      bottom_nav_html = view |> element(~s(nav[data-role="bottom-nav"])) |> render()

      assert nav_html =~ ~s(href="/plan")
      assert nav_html =~ ~s(href="/shop")
      assert nav_html =~ ~s(href="/settings")
      refute nav_html =~ ~s(href="/recipes")
      refute nav_html =~ ~s(href="/prep")
      refute nav_html =~ ~s(href="/deals")
      refute nav_html =~ ~s(href="/inbox")
      refute nav_html =~ ~s(href="/cooking")

      assert bottom_nav_html =~ ~s(href="/plan")
      assert bottom_nav_html =~ ~s(href="/shop")
      refute bottom_nav_html =~ ~s(href="/settings")
      refute bottom_nav_html =~ ~s(href="/recipes")
      refute bottom_nav_html =~ ~s(href="/prep")
      refute bottom_nav_html =~ ~s(href="/deals")
      refute bottom_nav_html =~ ~s(href="/inbox")
      refute bottom_nav_html =~ ~s(href="/cooking")
    end
  end

  test "review pill shows when runs need attention", %{conn: conn, user: user} do
    household_id = Tore.Household.get_household!().id
    {:ok, pid} = Tore.Harness.ProjectorSupervisor.start_or_lookup(household_id)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    open_needs_user_run(household_id, user.id)
    Process.sleep(50)

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ ~s(data-role="review-pill")
  end

  test "review pill is absent when nothing needs review", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    refute html =~ ~s(data-role="review-pill")
  end
end
