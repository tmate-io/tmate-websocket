defmodule Tmate do
  use Application

  def host do
    node() |> to_string |> String.split("@") |> Enum.at(1) |> String.split(".") |> Enum.at(0)
  end

  def start(_type, _args) do
    import Supervisor.Spec

    {:ok, daemon_options} = Application.fetch_env(:tmate, :daemon)
    {:ok, websocket_options} = Application.fetch_env(:tmate, :websocket)

    children = [
      :ranch.child_spec(:daemon_tcp, 3, :ranch_tcp, daemon_options[:ranch_opts],
                        Tmate.DaemonTcp, []),
      worker(Tmate.SessionRegistry, [[name: Tmate.SessionRegistry]]),
    ]

    children = unless websocket_options[:enabled] == false do
      cowboy_opts = [env: [dispatch: Tmate.WebSocket.cowboy_dispatch], compress: true]
      children ++ [
        :ranch.child_spec(:websocket_tcp, 3, websocket_options[:listener], websocket_options[:ranch_opts],
                          :cowboy_protocol, cowboy_opts)
      ]
    else
      children
    end

    Supervisor.start_link(children, [strategy: :one_for_one, name: Tmate.Supervisor])
  end
end
