use Mix.Config

config :logger, :console,
  format: "[$level] $message\n"

config :tmate, :daemon,
  hmac_key: "VlCkxXLjzaFravvNSPpOdoAffaQHRNVHeSBNWUcfLDYTYHuaYQsWwyCjrSJAJUSr"

config :tmate, :websocket,
  listener: :ranch_tcp,
  ranch_opts: [port: 4001],
  host: "localhost"

config :tmate, :master,
  nodes: ['master@erlmaster.default.svc.cluster.local'],
  session_url_fmt: "http://localhost:4000/t/%s"


#### The following shows a config that would be for supporting only webhooks

# config :tmate, :websocket,
  # enabled: false

# config :tmate, :webhook,
  # urls: ["http://localhost:4567/events"]

# config :tmate, :master,
  # session_url_fmt: "disabled"
