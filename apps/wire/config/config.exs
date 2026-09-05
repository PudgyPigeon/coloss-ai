import Config

config :wire, WireWeb.Endpoint,
  # set to 1000+ or comment out for production
  http: [port: 4000, transport_options: [num_acceptors: 5]],
  server: true,
  # Generate a real one with: mix phx.gen.secret
  secret_key_base: "LlLUf20c8lipR8KSUIw/WGdGOFPupbLKxQ4UWQ3Sk3Zh45LNVY0Rqt0RKzvBu0iS",
  render_errors: [
    formats: [html: WireWeb.ErrorHTML, json: WireWeb.ErrorHTML],
    layout: false
  ],
  # mix phx.gen.secret 32
  live_view: [signing_salt: "KvKm4mt0sXwI7PjSqxa3rSH9Cig9W+NI"]

config :phoenix, :json_library, Jason

config :os_mon,
  start_memsup: false,
  start_disksup: false,
  start_cpu_sup: false

# import_config "#{config_env()}.exs"
