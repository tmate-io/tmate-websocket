use Mix.Config

config :tmate, :daemon,
  port: 7000

config :tmate, :websocket,
  port: 4001

config :logger, :console,
  format: "[$level] $message\n"
