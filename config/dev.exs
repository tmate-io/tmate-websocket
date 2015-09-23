use Mix.Config

config :tmate, :app,
  reload_code: true

config :tmate, :daemon,
  port: 7000

config :tmate, :websocket,
  port: 8081

config :logger, :console,
  format: "[$level] $message\n"
