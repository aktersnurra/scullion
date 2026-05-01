defmodule ScullionWeb.Router do
  use ScullionWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ScullionWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug ScullionWeb.Plugs.Auth
  end

  # Public routes — no authentication required
  scope "/", ScullionWeb do
    pipe_through :browser

    live "/setup", SetupLive
    live "/login", LoginLive
  end

  # Authenticated users (member + admin)
  scope "/", ScullionWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated,
      on_mount: [{ScullionWeb.Live.Auth, :require_authenticated}] do
      live "/", PlannerLive
      live "/recipes", RecipeLive
      live "/groceries", GroceryLive
      live "/prep", PrepLive
      live "/deals", DealsLive
      live "/pantry", PantryLive
      live "/costs", CostLive
    end
  end

  # Admin only
  scope "/", ScullionWeb do
    pipe_through [:browser, :require_auth]

    live_session :admin,
      on_mount: [{ScullionWeb.Live.Auth, :require_admin}] do
      live "/settings", SettingsLive
    end
  end
end
