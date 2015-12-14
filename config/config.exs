use Mix.Config

import_config "#{Mix.env}.exs"

config :logger,
  backends: [:console, Rollbax.Notifier]

config :logger, Rollbax.Notifier,
  level: :error

config :rollbax,
  access_token: "cbf96daf284c4c85b608e86aa3def4c0",
  environment: Mix.env
