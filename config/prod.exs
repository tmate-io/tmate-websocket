use Mix.Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:session_id]

import_config "prod.secret.exs"
