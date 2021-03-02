use Mix.Config
# XXX The configuration file is evalated at compile time,
# and re-evaluated at runtime.

config :logger, :console,
  format: "$metadata[$level] $message\n",
  metadata: [:token, :id],
  level: :info

config :tmate, :daemon,
  hmac_key: System.get_env("DAEMON_HMAC_KEY")

websocket_ranch_opts = if System.get_env("SSL_KEY_FILE") do
  [listener: :ranch_ssl,
   ranch_opts: [
     port: System.get_env("WEBSOCKET_PORT", "4001") |> String.to_integer(),
     keyfile: System.get_env("SSL_KEY_FILE"),
     certfile: System.get_env("SSL_CERT_FILE"),
     cacertfile: System.get_env("SSL_CACERT_FILE")]]
else
  [listener: :ranch_tcp,
   ranch_opts: [port: System.get_env("WEBSOCKET_PORT", "4001") |> String.to_integer()]]
end

config :tmate, :websocket, Keyword.merge(websocket_ranch_opts,
  cowboy_opts: %{
    compress: true,
    proxy_header: System.get_env("USE_PROXY_PROTOCOL") == "1"},
  base_url: System.get_env("WEBSOCKET_BASE_URL"),
  trust_x_real_ip: System.get_env("TRUST_X_REAL_IP") == "1"
)

config :tzdata, :autoupdate, :disabled

config :tmate, :webhook,
  webhooks: [
    [url: "#{System.get_env("MASTER_BASE_URL")}internal_api/webhook",
     userdata: "#{System.get_env("INTERNAL_API_AUTH_TOKEN")}"]],
  max_attempts: 16, # ~2.7 hours of retries
  initial_retry_interval: 300

config :tmate, :master,
  user_facing_base_url: System.get_env("USER_FACING_BASE_URL"),
  internal_api: [base_url: "#{System.get_env("MASTER_BASE_URL")}internal_api",
                 auth_token: System.get_env("INTERNAL_API_AUTH_TOKEN")]
