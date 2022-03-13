use Mix.Config

config :logger,
  backends: [:console]

config :logger, :console,
  level: :debug

config :tmate, :daemon,
  ranch_opts: [port: 4002, max_connections: 10000],
  tmux_socket_path: "/tmp/tmate/sessions"

config :tmate, :webhook,
  webhooks: [],
  max_attempts: 3,
  initial_retry_interval: 300


import_config "#{Mix.env}.exs"
