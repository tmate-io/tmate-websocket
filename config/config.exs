use Mix.Config

config :logger,
  backends: [:console]

config :logger, :console,
  level: :debug

config :tmate, :daemon,
  ranch_opts: [port: 4002],
  tmux_socket_path: "/tmp/tmate/sessions"

config :tmate, :webhook,
  webhooks: [
    [url: "http://master:4000/wsapi/webhook",
     userdata: "webhookkey"]],
  max_attempts: 3,
  initial_retry_interval: 300


import_config "#{Mix.env}.exs"
