defmodule ToreWeb.PantryLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Tore.{Accounts, Pantry}

  setup do
    {:ok, {user, _code}} = Accounts.create_user(%{name: "Tester"})
    %{conn: build_conn(), user: user}
  end

  defp authed(conn, user), do: Plug.Test.init_test_session(conn, %{user_id: user.id})

  test "renders empty pantry", %{conn: conn, user: user} do
    conn = authed(conn, user)
    {:ok, _lv, html} = live(conn, "/settings/pantry")
    assert html =~ "Inget i skafferiet än"
  end

  test "renders existing items", %{conn: conn, user: user} do
    conn = authed(conn, user)
    {:ok, _} = Pantry.add_item(%{name: "Havregryn", quantity: Decimal.new("500"), unit: "g"})
    {:ok, _lv, html} = live(conn, "/settings/pantry")
    assert html =~ "Havregryn"
    assert html =~ "500"
  end

  test "old /pantry route no longer exists", %{conn: conn} do
    conn = get(conn, "/pantry")
    assert conn.status == 404
  end

  test "remove_item removes a pantry item", %{conn: conn, user: user} do
    conn = authed(conn, user)

    {:ok, item} =
      Tore.Pantry.add_item(%{name: "olive oil", quantity: Decimal.new(1), unit: "bottle"})

    {:ok, view, _html} = live(conn, "/settings/pantry")
    assert render(view) =~ "Olive oil"

    view |> element("button[phx-value-id=\"#{item.id}\"]") |> render_click()
    refute render(view) =~ "Olive oil"
  end
end
