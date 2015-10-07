defmodule Tmate.WebSocket do
  require Logger
  require Tmate.ProtocolDefs, as: P

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

    case Tmate.SessionRegistry.get_session(Tmate.SessionRegistry, session_token) do
      {mode, session} -> {:upgrade, :protocol, :cowboy_websocket, req, %{session: session, access_mode: mode}}
      :error -> {:ok, req, [404, [], "Session not found"]}
    end
  end

  def handle(req, args) do
    {:ok, req} = apply(Request, :reply, args ++ [req])
    {:ok, req, :nostate}
  end

  def send_msg(ws, msg) do
    send(ws, {:send_msg, msg})
  end

  def websocket_init(_transport, req, state) do
    {{ip, _port}, req} = Request.peer(req)
    ip = :inet_parse.ntoa(ip)
    Logger.info("Accepted websocket connection (ip=#{ip}) (access_mode=#{state.access_mode})")

    Process.monitor(state.session)

    :ok = Tmate.Session.ws_request_sub(state.session, self, [ip_address: ip])

    start_ping_timer
    {:ok, req, state}
  end

  def websocket_handle({:binary, msg}, req, %{access_mode: :rw} = state) do
    handle_ws_msg(state, deserialize_msg!(msg))
    {:ok, req, state}
  end

  def websocket_handle({:binary, _msg}, req, state) do
    {:ok, req, state}
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

  def websocket_info({:send_msg, msg}, req, state) do
     {:reply, serialize_msg!(msg), req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    Logger.info("Closed websocket connection")
    :ok
  end

  def terminate(_reason, _req, _state) do
    :ok
  end

  # TODO validate types
  defp handle_ws_msg(state, [P.tmate_ws_pane_keys, pane_id, data])
      when is_integer(pane_id) and pane_id >= 0 and is_binary(data) do
    :ok = Tmate.Session.send_pane_keys(state.session, pane_id, data)
  end

  defp handle_ws_msg(state, [P.tmate_ws_exec_cmd, cmd]) when is_binary(cmd) do
    :ok = Tmate.Session.send_exec_cmd(state.session, 0, cmd)
  end

  defp handle_ws_msg(state, [P.tmate_ws_resize, [max_cols, max_rows]])
      when is_integer(max_cols) and max_cols >= 0 and
           is_integer(max_rows) and max_rows >= 0 do
    :ok = Tmate.Session.notify_resize(state.session, self, {max_cols, max_rows})
  end

  defp handle_ws_msg(_state, msg) do
    Logger.warn("Unknown ws msg: #{inspect(msg)}")
  end

  defp serialize_msg!(msg) do
    {:binary, MessagePack.pack!(msg, enable_string: true)}
  end

  defp deserialize_msg!(msg) do
    MessagePack.unpack!(msg)
  end
end
