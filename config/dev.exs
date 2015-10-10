use Mix.Config

config :tmate, :daemon,
  port: 4002

config :tmate, :websocket,
  port: 4001

config :logger, :console,
  format: "[$level] $message\n"

config :tmate, :master,
  nodes: [:master]
