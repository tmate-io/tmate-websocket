use Mix.Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:session_id]

config :tmate, :websocket,
  listener: :ranch_ssl

config :logger, level: :debug

import_config "prod.secret.exs"
