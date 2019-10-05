use Mix.Config

config :logger, :console,
  format: "[$level] $message\n"

config :tmate, :daemon,
  hmac_key: "VlCkxXLjzaFravvNSPpOdoAffaQHRNVHeSBNWUcfLDYTYHuaYQsWwyCjrSJAJUSr"

config :tmate, :websocket,
  listener: :ranch_tcp,
  ranch_opts: [port: 4001],
  cowboy_opts: %{compress: true},
  base_url: "ws://localhost:4001/",
  wsapi_key: "webhookkey"

config :tmate, :master,
  user_facing_base_url: "http://localhost:4000/"
