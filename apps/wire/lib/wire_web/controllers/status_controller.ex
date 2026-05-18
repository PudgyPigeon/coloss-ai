defmodule WireWeb.StatusController do
  use Phoenix.Controller, formats: [:html, :json]

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
