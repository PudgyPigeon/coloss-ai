defmodule WireWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :wire

  @session_options [
    store: :cookie,
    key: "_wire_key",
    signing_salt: "SomethingRandomAndSecret"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug(Plug.Static, at: "/", from: :wire, gzip: false)
  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(WireWeb.Router)
end
