defmodule Wire.Switchboard.Router do
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

    get("/", Wire.Switchboard.StatusController, :index)

    live_dashboard(
      "/dashboard",
      metrics: Wire.Telemetry,
      colors: [
        primary: "#00ff00",   # Neon Green for buttons/headers
        secondary: "#003300"  # Dark Green for accents
      ])
  end

  scope("/api") do
    pipe_through(:api)
    get("/health", Wire.Switchboard.StatusController, :health)
  end
end
