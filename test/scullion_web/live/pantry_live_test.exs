defmodule ScullionWeb.PantryLiveTest do
  use ScullionWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Scullion.{Accounts, Pantry}

  setup do
    {:ok, {user, _code}} = Accounts.create_user(%{name: "Tester"})
    conn = build_conn() |> Plug.Test.init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  test "renders empty pantry", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/pantry")
    assert html =~ "Skafferi"
    assert html =~ "Inget i skafferiet"
  end

  test "renders existing items", %{conn: conn} do
    {:ok, _} = Pantry.add_item(%{name: "Havregryn", quantity: Decimal.new("500"), unit: "g"})
    {:ok, _lv, html} = live(conn, "/pantry")
    assert html =~ "Havregryn"
    assert html =~ "500"
  end

  test "add item via form appears in list", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/pantry")
    html = lv |> form("form", %{name: "Linser", quantity: "400", unit: "g", category: "legumes", expires_at: ""}) |> render_submit()
    assert html =~ "Linser"
  end

  test "remove item disappears from list", %{conn: conn} do
    {:ok, item} = Pantry.add_item(%{name: "Tonfisk"})
    {:ok, lv, _html} = live(conn, "/pantry")
    html = lv |> element("button[phx-value-id='#{item.id}']") |> render_click()
    refute html =~ "Tonfisk"
  end
end
