use Mix.Config

config :logger,
  backends: [:console]

config :logger, :console,
  level: :debug

config :tmate, :daemon,
  ranch_opts: [port: 4002],
  tmux_socket_path: "/tmp/tmate/sessions"

config :tmate, :master,
  session_url_fmt: "http://localhost:4000/t/%s"

config :tmate, :webhook,
  allow_user_defined_urls: true,
  urls: []

import_config "#{Mix.env}.exs"
