use Mix.Config

config :logger, :console,
  level: :warn,
  format: "[$level] $message\n"

config :tmate, :daemon,
  hmac_key: "key"

config :tmate, :websocket,
  enabled: false,
  wsapi_key: "webhookkey"

config :tmate, :master,
  user_facing_base_url: "http://localhost:4000/"
