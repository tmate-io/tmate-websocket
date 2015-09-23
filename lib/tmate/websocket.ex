defmodule Tmate.WebSocket do
  require Logger

  alias :cowboy_req, as: Request

  @ping_interval_sec 60

  def cowboy_dispatch do
    :cowboy_router.compile([{:_, [
      {"/ws/session/:session_token", __MODULE__, []},
    ]}])
  end

  require IEx
  def init({_transport, :http}, req, _opts) do
    {session_token, req} = Request.binding(:session_token, req)
    Logger.metadata([session_token: session_token])
    # TODO Check the request origin
    case Tmate.SessionRegistery.get_session(Tmate.SessionRegistery, session_token) do
      {mode, session} -> {:upgrade, :protocol, :cowboy_websocket, req, %{session: session, access_mode: mode}}
      :error -> {:ok, req, [404, [], "Session not found"]}
    end
  end

  def handle(req, args) do
    {:ok, req} = apply(Request, :reply, args ++ [req])
    {:ok, req, :nostate}
  end

  def websocket_init(_transport, req, state) do
    Logger.debug("Accepted websocket connection (access_mode=#{state.access_mode})")
    Process.monitor(state.session)
    start_ping_timer
    {:ok, req, state}
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

  defp start_ping_timer() do
    :erlang.start_timer(@ping_interval_sec * 1000, self, :ping)
  end

  def websocket_info({:timeout, _ref, :ping}, req, state) do
    {:reply, :ping, req, state}
  end

  def websocket_info({:DOWN, _ref, _type, _pid, _info}, req, state) do
    {:reply, :close, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    Logger.debug("Closed websocket connection")
    :ok
  end

  def terminate(_reason, _req, _state) do
    :ok
  end
end
