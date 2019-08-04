use Mix.Config

config :logger, :console,
  format: "[$level] $message\n"

config :tmate, :daemon,
  hmac_key: "key"

config :tmate, :websocket,
  listener: :ranch_tcp,
  ranch_opts: [port: 4001],
  host: "localhost",
  cookie_opts: [
    key: "tmate_session",
    secret_key_base: "rzC2wqnmk0VeKRZHiMtPDAkd5QeWdPSSX2H9pknPBgb4rdOA7TEqMq9Umm5bjFPs",
    signing_salt: "PlqZqmWt",
    encryption_salt: "vIeLihup"]

config :tmate, :master,
  nodes: ['master@erlmaster.default.svc.cluster.local']

config :tmate, :webhook,
  enabled: false

#### Events only

# config :tmate, :websocket,
  # enabled: false

# config :tmate, :webhook,
  # urls: ["http://localhost:4567/events"]

# config :tmate, :master,
  # session_url_fmt: "disabled"
