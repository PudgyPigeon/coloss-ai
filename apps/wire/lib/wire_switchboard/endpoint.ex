defmodule Wire.Switchboard.Endpoint do
  use Phoenix.Endpoint, otp_app: :wire

  @session_options [
    store: :cookie,
    key: "_wire_key",
    signing_salt: "SomethingRandomAndSecret"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Session, @session_options

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()


  plug(Wire.Switchboard.Router)
end
