use Mix.Config

config :logger,
  backends: [:console]

config :logger, :console,
  level: :debug

config :tmate, :daemon,
  ranch_opts: [port: 4002],
  tmux_socket_path: "/tmp/tmate/sessions"

config :tmate, :webhook,
  enabled: true,
  allow_user_defined_urls: true,
  urls: []

config :tmate, :master,
  nodes: []

import_config "#{Mix.env}.exs"
