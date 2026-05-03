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
      assert html =~ "digit-1"
    end

    test "redirects authenticated user to /", %{conn: conn, user: user} do
      conn = conn |> Plug.Test.init_test_session(%{user_id: user.id})
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/login")
    end
  end

  describe "digit entry" do
    test "accumulates digits", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")
      render_click(lv, "digit", %{"value" => "1"})
      render_click(lv, "digit", %{"value" => "2"})
      html = render_click(lv, "digit", %{"value" => "3"})
      assert length(Regex.scan(~r/●/, html)) == 3
    end

    test "backspace removes last digit", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")
      render_click(lv, "digit", %{"value" => "1"})
      render_click(lv, "digit", %{"value" => "2"})
      html = render_click(lv, "backspace", %{})
      assert length(Regex.scan(~r/●/, html)) == 1
    end

    test "does not exceed 16 digits", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")

      for _ <- 1..20 do
        render_click(lv, "digit", %{"value" => "1"})
      end

      html = render(lv)
      assert length(Regex.scan(~r/●/, html)) == 16
    end
  end

  describe "submit" do
    test "shows error when fewer than 16 digits entered", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")

      for _ <- 1..5 do
        render_click(lv, "digit", %{"value" => "1"})
      end

      html = render_click(lv, "submit", %{})
      assert html =~ "Enter all 16 digits"
    end

    test "redirects on valid code", %{conn: conn, code: code} do
      {:ok, lv, _} = live(conn, "/login")

      for digit <- String.graphemes(code) do
        render_click(lv, "digit", %{"value" => digit})
      end

      assert {:error, {:live_redirect, %{to: "/login/session?t=" <> _}}} =
               render_click(lv, "submit", %{})
    end

    test "shows error for invalid code", %{conn: conn} do
      {:ok, lv, _} = live(conn, "/login")

      for _ <- 1..16 do
        render_click(lv, "digit", %{"value" => "0"})
      end

      html = render_click(lv, "submit", %{})
      assert html =~ "Invalid code"
    end
  end
end
