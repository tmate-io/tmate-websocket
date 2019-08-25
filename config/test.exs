use Mix.Config

config :logger, :console,
  level: :warn,
  format: "[$level] $message\n"

config :tmate, :websocket,
  enabled: false

config :tmate, :daemon,
  hmac_key: "key"

config :tmate, :master,
  nodes: [],
  session_url_fmt: "http://localhost:4000/t/%s"
