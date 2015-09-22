defmodule Tmate.WebSocket do
  require Logger

  alias :cowboy_req, as: Request

  @ping_interval_sec 60

  def cowboy_dispatch do
    :cowboy_router.compile([{:_, [
      {"/ws/session/:session_token", __MODULE__, []},
    ]}])
  end

  def init({_transport, :http}, _req, _opts) do
    {:upgrade, :protocol, :cowboy_websocket}
  end

  def websocket_init(_transport, req, _opts) do
    {session_token, req} = Request.binding(:session_token, req)

    Logger.metadata([session_token: session_token])
    Logger.info("Accepted websocket connection")

    start_ping_timer

    {:ok, req, %{session_token: session_token}}
  end

  def websocket_handle({:text, msg}, req, state) do
    case msg do
      "exit" -> {:reply, :close, req, state}
      _ ->      {:reply, {:text, "you said: #{msg}"}, req, state}
    end
  end

  def websocket_handle({:pong, _}, req, state) do
    start_ping_timer
    {:ok, req, state}
  end

  def websocket_handle(data, req, state) do
    Logger.warn("Unhandled websocket data: #{inspect(data)}")
    {:ok, req, state}
  end

  defp start_ping_timer() do
    :erlang.start_timer(@ping_interval_sec * 1000, self, :ping)
  end

  def websocket_info({:timeout, _ref, :ping}, req, state) do
    {:reply, :ping, req, state}
  end

  def websocket_info(_info, req, state) do
    {:ok, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    Logger.info("Closed websocket connection")
    :ok
  end
end
