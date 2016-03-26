use Mix.Config

config :logger, :console,
  level: :warn,
  format: "[$level] $message\n"

config :rollbax, enabled: false

config :tmate, :websocket,
  enabled: false
