defmodule WireWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope("/") do
    pipe_through(:browser)

    get("/", WireWeb.StatusController, :index)

    live("/swarm", WireWeb.SwarmDashboardLive)

    live_dashboard(
      "/dashboard",
      metrics: Wire.Telemetry,
      colors: [
        # Neon Green for buttons/headers
        primary: "#00ff00",
        # Dark Green for accents
        secondary: "#003300"
      ]
    )
  end

  scope("/api") do
    pipe_through(:api)
    get("/health", WireWeb.StatusController, :health)
  end
end
