defmodule ToreWeb.KioskLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    {:ok, {_record, raw_token}} = Tore.Accounts.generate_device_token("Kitchen tablet")

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"device_token" => raw_token})

    %{conn: conn}
  end

  test "unauthenticated request redirects" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/kiosk")
  end

  test "authenticated request mounts and shows Tonight heading", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/kiosk")
    assert html =~ "Tonight"
  end

  test "shows No meal planned when no recipe assigned", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/kiosk")
    assert html =~ "No meal planned"
  end
end
