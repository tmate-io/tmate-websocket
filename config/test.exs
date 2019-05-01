use Mix.Config

config :logger, :console,
  level: :warn,
  format: "[$level] $message\n"

config :tmate, :websocket,
  enabled: false

config :tmate, :daemon,
  hmac_key: "key"
