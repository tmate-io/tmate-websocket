use Mix.Config

config :tmate, :websocket,
  listener: :ranch_tcp,
  ranch_opts: [port: 4001],
  host: "localhost",
  cookie_opts: [
    key: "tmate_session",
    secret_key_base: "rzC2wqnmk0VeKRZHiMtPDAkd5QeWdPSSX2H9pknPBgb4rdOA7TEqMq9Umm5bjFPs",
    signing_salt: "PlqZqmWt",
    encryption_salt: "vIeLihup"]

config :logger, :console,
  format: "[$level] $message\n"

config :tmate, :master,
  nodes: [:master]

config :rollbax, enabled: false
