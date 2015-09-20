defmodule Tmate do
  use Application

  def start(_type, _args) do
    listen_options = [
      port: 7000,
      max_connections: :infinity,
    ]

    children = [
      :ranch.child_spec(:tcp_daemon, 10, :ranch_tcp, listen_options, Tmate.TcpDaemon, [])
    ]
    Supervisor.start_link(children, [strategy: :one_for_one, name: Tmate.Supervisor])
  end
end
