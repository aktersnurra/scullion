defmodule ScullionWeb.LoginLiveTest do
  use ScullionWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Scullion.Accounts

  setup do
    {:ok, {user, code}} = Accounts.create_admin("Gustaf")
    %{user: user, code: code}
  end

  describe "GET /login" do
    test "renders numpad", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/login")
      assert html =~ "Scullion"
      assert html =~ "phx-click=\"digit\""
    end

    test "redirects authenticated user to /", %{conn: conn, user: user} do
      conn = conn |> Plug.Test.init_test_session(%{user_id: user.id})
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/login")
    end
  end

  describe "digit entry" do
    test "accumulates digits", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")
      lv |> element("button[phx-value-value=\"1\"]") |> render_click()
      lv |> element("button[phx-value-value=\"2\"]") |> render_click()
      html = lv |> element("button[phx-value-value=\"3\"]") |> render_click()
      # 3 filled dots in the display
      assert length(Regex.scan(~r/●/, html)) == 3
    end

    test "backspace removes last digit", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")
      lv |> element("button[phx-value-value=\"1\"]") |> render_click()
      lv |> element("button[phx-value-value=\"2\"]") |> render_click()
      html = lv |> element("button[phx-click=\"backspace\"]") |> render_click()
      assert length(Regex.scan(~r/●/, html)) == 1
    end

    test "does not exceed 16 digits", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")

      for _ <- 1..20 do
        lv |> element("button[phx-value-value=\"1\"]") |> render_click()
      end

      html = render(lv)
      assert length(Regex.scan(~r/●/, html)) == 16
    end
  end

  describe "submit" do
    test "shows error when fewer than 16 digits entered", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")

      for _ <- 1..5 do
        lv |> element("button[phx-value-value=\"1\"]") |> render_click()
      end

      # Send event directly since the submit button is disabled
      html = render_click(lv, "submit", %{})
      assert html =~ "Enter all 16 digits"
    end

    test "redirects on valid code", %{conn: conn, code: code} do
      {:ok, lv, _} = live(conn, "/login")

      for digit <- String.graphemes(code) do
        lv |> element("button[phx-value-value=\"#{digit}\"]") |> render_click()
      end

      assert {:error, {:live_redirect, %{to: "/login/session?t=" <> _}}} =
               render_click(lv, "submit", %{})
    end

    test "shows error for invalid code", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")

      for _ <- 1..16 do
        lv |> element("button[phx-value-value=\"0\"]") |> render_click()
      end

      html = render_click(lv, "submit", %{})
      assert html =~ "Invalid code"
    end
  end
end
