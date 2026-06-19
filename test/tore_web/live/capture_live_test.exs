defmodule ToreWeb.CaptureLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  setup do
    {:ok, {user, _code}} = Tore.Accounts.create_admin("Gustaf")
    conn = build_conn() |> Plug.Test.init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  test "mount renders empty chat", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/capture")
    assert html =~ "Ask Tore"
  end

  test "sending a message appends user bubble", %{conn: conn} do
    Tore.MockLLM
    |> expect(:chat, fn _system, _messages, _opts ->
      {:ok, "Try making pasta tonight!",
       %{prompt_tokens: 10, completion_tokens: 8, cost_usd: 0.0001}}
    end)

    {:ok, lv, _html} = live(conn, "/capture")

    html =
      lv
      |> form("form", %{message: "What should I cook?"})
      |> render_submit()

    assert html =~ "What should I cook?"

    :timer.sleep(200)
    html = render(lv)
    assert html =~ "Try making pasta tonight!"
  end
end
