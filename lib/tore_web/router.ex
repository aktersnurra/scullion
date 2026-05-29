defmodule ToreWeb.Router do
  use ToreWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ToreWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ToreWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug ToreWeb.Plugs.Auth
  end

  # Public routes — no authentication required
  scope "/", ToreWeb do
    pipe_through :browser

    live "/setup", SetupLive
    live "/login", LoginLive
    get "/login/session", SessionController, :confirm
  end

  # Authenticated users (member + admin)
  scope "/", ToreWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated,
      on_mount: [{ToreWeb.Live.Auth, :require_authenticated}] do
      live "/", HomeLive
      live "/plan", PlannerLive
      live "/recipes", RecipeLive
      live "/groceries", GroceryLive
      live "/prep", PrepLive
      live "/deals", DealsLive
      live "/pantry", PantryLive
      live "/costs", CostLive
      live "/cooking", CookingLive
      live "/settings", SettingsLive
      live "/chat", ChatLive
      live "/review/:class/:id", ReviewLive
    end
  end
end
