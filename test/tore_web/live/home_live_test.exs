defmodule ToreWeb.HomeLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Tore.Accounts

  setup do
    {:ok, {user, _code}} = Accounts.create_admin("Gustaf")
    conn = build_conn() |> Plug.Test.init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  test "mounts without crash and shows tonight section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Ikväll"
  end

  test "shows nothing planned when no recipe assigned", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Inget planerat ikväll"
  end

  test "week strip renders 7 day chips", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    # Day names are rendered in Swedish (default locale)
    assert html =~ "Mån"
    assert html =~ "Tis"
    assert html =~ "Ons"
  end

  test "FAB renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Fråga Tore"
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
end
