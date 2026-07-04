defmodule ToreWeb.SettingsLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Tore.Accounts

  setup do
    {:ok, {user, _code}} = Accounts.create_admin("Gustaf")
    conn = build_conn() |> Plug.Test.init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  test "settings links to run history", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")

    assert html =~ ~s(href="/inbox")
    assert html =~ "Körhistorik"
  end
end
