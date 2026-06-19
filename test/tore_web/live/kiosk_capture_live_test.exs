defmodule ToreWeb.KioskCaptureLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  setup do
    {:ok, {_record, raw_token}} = Tore.Accounts.generate_device_token("Kitchen tablet")

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"device_token" => raw_token})

    %{conn: conn}
  end

  test "mounts and renders input", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/kiosk/capture")
    assert html =~ "Ask Tore"
  end

  test "sending a message triggers LLM and shows reply", %{conn: conn} do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages, _opts ->
      {:ok, "Cook at 180°C for 25 minutes.", %{}}
    end)

    {:ok, lv, _html} = live(conn, "/kiosk/capture")

    html = lv |> form("form", %{message: "How long to roast chicken?"}) |> render_submit()
    assert html =~ "How long to roast chicken?"

    :timer.sleep(200)
    assert render(lv) =~ "Cook at 180°C"
  end
end
