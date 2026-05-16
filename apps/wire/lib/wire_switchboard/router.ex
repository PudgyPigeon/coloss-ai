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

defmodule Wire.Switchboard.StatusController do
  use Phoenix.Controller

  def health(conn, _params) do
    json(conn, %{
      name: "THE WIRE",
      status: "ok",
      version: "0.0.1",
      node: node(),
      connections: length(Node.list())
    })
  end

  def index(conn, _params) do
    # Instead of json(conn, %{...}), we use html(conn, string)
    html(conn, """
    <!DOCTYPE html>
    <html style="background: #000; color: #0f0; font-family: monospace;">
      <head><title>THE WIRE</title></head>
      <body>
        <h1>[ SYSTEM ONLINE ]</h1>
        <p>NODE: #{node()}</p>
        <p>STATUS: Intercepting signals...</p>
        <p>Agentic swarm ready for telemetry...</p>
      </body>
    </html>
    """)
  end
end
