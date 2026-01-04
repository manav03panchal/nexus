defmodule NexusWeb.Router do
  use NexusWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {NexusWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Static assets (embedded for escript compatibility)
  scope "/assets", NexusWeb do
    get("/app.css", AssetsController, :css)
    get("/app.js", AssetsController, :js)
    get("/nexus-logo.png", AssetsController, :logo)
  end

  scope "/", NexusWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/task/:task_name", DashboardLive, :task)
  end

  # API endpoints for programmatic access
  scope "/api", NexusWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)
    get("/config", ConfigController, :show)
    post("/execute", ExecuteController, :create)
  end
end
