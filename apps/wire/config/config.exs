import Config

config :wire, Wire.Switchboard.Endpoint,
  http: [port: 4000],
  server: true,
  # Generate a real one with: mix phx.gen.secret
  secret_key_base: "LlLUf20c8lipR8KSUIw/WGdGOFPupbLKxQ4UWQ3Sk3Zh45LNVY0Rqt0RKzvBu0iS",
  render_errors: [
    formats: [html: Wire.Switchboard.ErrorHTML, json: Wire.Switchboard.ErrorHTML],
    layout: false
  ],
  live_view: [signing_salt: "KvKm4mt0sXwI7PjSqxa3rSH9Cig9W+NI"] # mix phx.gen.secret 32

config :phoenix, :json_library, Jason

config :os_mon,
  start_memsup: false,
  start_disksup: false,
  start_cpu_sup: false

# import_config "#{config_env()}.exs"
