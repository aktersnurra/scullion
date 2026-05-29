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
    assert html =~ "Tonight"
  end

  test "shows nothing planned when no recipe assigned", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Nothing planned for tonight"
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
    assert html =~ "Ask Tore"
  end
end
