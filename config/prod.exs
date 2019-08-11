use Mix.Config
# XXX The configuration file is evalated at compile time,
# and re-evaluated at runtime

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:session_id]

config :tmate, :daemon,
  hmac_key: System.get_env("DAEMON_HMAC_KEY")

config :tmate, :websocket,
  listener: :ranch_ssl,
  ranch_opts: [
    port: 4001,
    keyfile: System.get_env("SSL_KEY_FILE"),
    certfile: System.get_env("SSL_CERT_FILE"),
    cacertfile: System.get_env("SSL_CACERT_FILE")],
  host: System.get_env("HOST")

config :tmate, :master,
  nodes: ['master@erlmaster.default.svc.cluster.local'],
  session_url_fmt: "https://#{System.get_env("MASTER_HOST")}/t/%s"
