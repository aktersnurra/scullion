defmodule ToreWeb.ReviewLiveTest do
  use ToreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    if :ets.whereis(:chat_reviews) == :undefined do
      :ets.new(:chat_reviews, [:set, :public, :named_table])
    end

    {:ok, {user, _code}} = Tore.Accounts.create_admin("Gustaf")
    conn = build_conn() |> Plug.Test.init_test_session(%{user_id: user.id})
    %{conn: conn}
  end

  test "recipe review renders title and ingredients", %{conn: conn} do
    id = Ecto.UUID.generate()
    recipe = %{title: "Lasagne", ingredients: [%{name: "pasta"}], instructions: "Layer it."}
    :ets.insert(:chat_reviews, {id, %{class: :recipe, result: recipe}})

    {:ok, _view, html} = live(conn, ~p"/review/recipe/#{id}")
    assert html =~ "Lasagne"
    assert html =~ "pasta"
    assert html =~ "Inget sparat än"
  end

  test "unknown review id redirects home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/review/recipe/nonexistent-id")
  end
end
