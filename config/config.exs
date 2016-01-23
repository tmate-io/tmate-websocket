use Mix.Config

config :logger,
  backends: [:console, Rollbax.Notifier]

config :logger, Rollbax.Notifier,
  level: :error

config :rollbax,
  access_token: "cbf96daf284c4c85b608e86aa3def4c0",
  environment: Mix.env

config :tmate, :daemon,
  port: 4002

config :tmate, :master,
  session_url_fmt: "http://localhost:4000/t/%s"

import_config "#{Mix.env}.exs"
