defmodule ScullionWeb.SetupLiveTest do
  use ScullionWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Scullion.Accounts

  describe "GET /setup" do
    test "renders form when no admin exists", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/setup")
      assert html =~ "Welcome to Scullion"
      assert html =~ "Create admin account"
    end

    test "redirects to /login when setup already complete", %{conn: conn} do
      {:ok, _} = Accounts.create_admin("Existing Admin")
      assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, "/setup")
    end
  end

  describe "submit" do
    test "creates admin and shows code", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/setup")
      html = lv |> form("form", name: "Gustaf") |> render_submit()
      assert html =~ "Save this 16-digit code"
      assert html =~ "Go to login"
    end

    test "code is displayed in XXXX XXXX XXXX XXXX format", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/setup")
      html = lv |> form("form", name: "Gustaf") |> render_submit()
      assert html =~ ~r/\d{4} \d{4} \d{4} \d{4}/
    end

    test "shows error for blank name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/setup")
      html = lv |> form("form", name: "") |> render_submit()
      assert html =~ "Name is required"
    end

    test "setup is locked after first admin is created", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/setup")
      lv |> form("form", name: "Gustaf") |> render_submit()
      assert Accounts.setup_complete?()
    end
  end
end
