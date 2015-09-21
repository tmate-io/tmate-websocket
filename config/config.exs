use Mix.Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:session_token]

import_config "#{Mix.env}.exs"
