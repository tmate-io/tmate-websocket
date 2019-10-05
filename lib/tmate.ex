defmodule Tmate do
  use Application
  require Logger

  def host do
    node() |> to_string |> String.split("@") |> Enum.at(1) |> String.split(".") |> Enum.at(0)
  end

  def start(_type, _args) do
    import Supervisor.Spec

    {:ok, daemon_options} = Application.fetch_env(:tmate, :daemon)
    {:ok, websocket_options} = Application.fetch_env(:tmate, :websocket)
    {:ok, webhook_options} = Application.fetch_env(:tmate, :webhook)

    webhooks = webhook_options[:webhooks] |> Enum.map(& {Tmate.Webhook, &1})
    registry = {Tmate.SessionRegistry, Tmate.SessionRegistry}

    children = [
      :ranch.child_spec(:daemon_tcp, 3, :ranch_tcp, daemon_options[:ranch_opts],
                        Tmate.DaemonTcp, [webhooks: webhooks, registry: registry]),
      worker(Tmate.SessionRegistry, [[name: Tmate.SessionRegistry]]),
    ]

    children = unless websocket_options[:enabled] == false do
      cowboy_opts = Map.merge(%{env: %{dispatch: Tmate.WebApi.Router.cowboy_dispatch(webhooks)}},
                              websocket_options[:cowboy_opts])
      children ++ [
        :ranch.child_spec(:websocket_tcp, 3, websocket_options[:listener], websocket_options[:ranch_opts],
                          :cowboy_clear, cowboy_opts)
      ]
    else
      children
    end

    Logger.info("Starting websocket server")
    Supervisor.start_link(children, [strategy: :one_for_one, name: Tmate.Supervisor])
  end
end
