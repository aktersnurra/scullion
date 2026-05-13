defmodule ScullionWeb.PlannerLiveTest do
  use ScullionWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Mox

  alias Scullion.{Accounts, Recipes, Handlers.PlanningHandler}

  setup :verify_on_exit!

  setup do
    {:ok, {user, _code}} = Accounts.create_admin("Gustaf")
    {:ok, recipe} = Recipes.create(%{title: "Roast chicken", recipe_type: :meal, base_servings: 6, prep_time_minutes: 10, cook_time_minutes: 60})
    %{user: user, recipe: recipe}
  end

  defp authed(conn, user), do: Plug.Test.init_test_session(conn, %{user_id: user.id})

  defp this_plan_id do
    today = Date.utc_today()
    dow = Date.day_of_week(today)
    week_start = Date.add(today, -(dow - 1))
    "plan:#{Date.to_iso8601(week_start)}"
  end

  describe "slot modal" do
    test "open_slot loads suggestions and shows modal", %{conn: conn, user: user, recipe: recipe} do
      conn = authed(conn, user)
      {:ok, lv, _html} = live(conn, "/")

      html = render_click(lv, "open_slot", %{"slot_key" => "mon_dinner"})
      # modal title
      assert html =~ "Monday · Dinner"

      # eventually the recipe shows up either in suggested or all-recipes list
      :timer.sleep(150)
      html = render(lv)
      assert html =~ recipe.title
    end

    test "save with selected recipe fires assign and closes modal", %{conn: conn, user: user, recipe: recipe} do
      conn = authed(conn, user)
      {:ok, lv, _html} = live(conn, "/")
      render_click(lv, "open_slot", %{"slot_key" => "tue_dinner"})
      :timer.sleep(150)
      render_click(lv, "pick_recipe", %{"id" => to_string(recipe.id)})
      render_click(lv, "save_slot", %{})

      {:ok, state} = PlanningHandler.load_plan(this_plan_id())
      assert state.slots["tue_dinner"].recipe_id == recipe.id
    end

    test "leftover day chips create leftover events on save", %{conn: conn, user: user, recipe: recipe} do
      conn = authed(conn, user)
      {:ok, lv, _html} = live(conn, "/")
      render_click(lv, "open_slot", %{"slot_key" => "mon_dinner"})
      :timer.sleep(150)
      render_click(lv, "pick_recipe", %{"id" => to_string(recipe.id)})
      render_click(lv, "toggle_leftover_day", %{"day" => "tue_dinner"})
      render_click(lv, "save_slot", %{})

      {:ok, state} = PlanningHandler.load_plan(this_plan_id())
      assert state.slots["mon_dinner"].recipe_id == recipe.id
      assert state.slots["tue_dinner"].leftover == true
    end

    test "'No dinner planned' toggle saves as MealSkipped", %{conn: conn, user: user, recipe: recipe} do
      # Pre-assign a meal so skip has something to act on
      PlanningHandler.assign_recipe(this_plan_id(), "wed_dinner", recipe.id, 4)

      conn = authed(conn, user)
      {:ok, lv, _html} = live(conn, "/")
      render_click(lv, "open_slot", %{"slot_key" => "wed_dinner"})
      :timer.sleep(150)
      render_click(lv, "toggle_skipped", %{})
      render_click(lv, "save_slot", %{})

      {:ok, state} = PlanningHandler.load_plan(this_plan_id())
      assert state.slots["wed_dinner"].skipped == true
    end

    test "search_slot_recipes event updates search state", %{conn: conn, user: user} do
      conn = authed(conn, user)
      {:ok, lv, _html} = live(conn, "/")
      render_click(lv, "open_slot", %{"slot_key" => "mon_dinner"})
      :timer.sleep(150)
      # drive the event directly rather than via form helper (avoids phx-click-away)
      html = render_change(lv, "search_slot_recipes", %{"q" => "salmon"})
      # modal still visible and search query reflected in input value
      assert html =~ ~s(value="salmon") or html =~ "salmon"
    end

    test "servings stepper bounded to 1..12", %{conn: conn, user: user} do
      conn = authed(conn, user)
      {:ok, lv, _html} = live(conn, "/")
      render_click(lv, "open_slot", %{"slot_key" => "mon_dinner"})
      :timer.sleep(150)

      # default 4 → click dec 5 times, should land on 1
      for _ <- 1..5, do: render_click(lv, "dec_servings", %{})
      html = render(lv)
      # extract the displayed number — the modal renders portions as "1"
      assert html =~ ~r/>1<\/span>\s*<button[^>]*phx-click="inc_servings"/

      # click inc 20 times, should cap at 12
      for _ <- 1..20, do: render_click(lv, "inc_servings", %{})
      html = render(lv)
      assert html =~ ~r/>12<\/span>\s*<button[^>]*phx-click="inc_servings"/
    end
  end
end
