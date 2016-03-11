use Mix.Config

config :logger,
  backends: [:console, Rollbax.Notifier]

config :logger, :console,
  level: :debug

config :logger, Rollbax.Notifier,
  level: :error

config :rollbax,
  enabled: false,
  environment: Mix.env,
  access_token: "XXX"

config :tmate, :daemon,
  port: 4002

config :tmate, :master,
  session_url_fmt: "http://localhost:4000/t/%s"

config :tmate, :webhook,
  urls: []

config :ex_statsd,
  namespace: 'tmate'

import_config "#{Mix.env}.exs"
