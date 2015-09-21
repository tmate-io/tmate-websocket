defmodule Tmate do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    listen_options = [
      port: 7000,
      max_connections: :infinity,
    ]

    children = [
      :ranch.child_spec(:daemon_tcp, 1, :ranch_tcp, listen_options, Tmate.DaemonTcp, []),
      supervisor(Tmate.SessionRegistery, [[name: Tmate.SessionRegistery]]),
    ]
    Supervisor.start_link(children, [strategy: :one_for_one, name: Tmate.Supervisor])
  end
end
