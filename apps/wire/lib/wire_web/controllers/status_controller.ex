defmodule WireWeb.StatusController do
  @moduledoc """
  Status controller offering basic health telemetry and standard system landing page.
  """

  use Phoenix.Controller, formats: [:html, :json]

  @spec health(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def health(conn, _params) do
    app_name = :wire |> to_string() |> String.upcase()
    version = :wire |> Application.spec(:vsn) |> to_string()

    json(conn, %{
      name: "THE " <> app_name,
      status: "ok",
      version: version,
      node: node(),
      connections: length(Node.list())
    })
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    app_name = :wire |> to_string() |> String.upcase()
    title = "THE " <> app_name

    # Instead of json(conn, %{...}), we use html(conn, string)
    html(conn, """
    <!DOCTYPE html>
    <html style="background: #000; color: #0f0; font-family: monospace;">
      <head><title>#{title}</title></head>
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
