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

    case Tmate.SessionRegistery.get_session(Tmate.SessionRegistery, session_token) do
      {mode, session} -> {:upgrade, :protocol, :cowboy_websocket, req, %{session: session, access_mode: mode}}
      :error -> {:ok, req, [404, [], "Session not found"]}
    end
  end

  def handle(req, args) do
    {:ok, req} = apply(Request, :reply, args ++ [req])
    {:ok, req, :nostate}
  end

  defp do_sync_call(ws, args) do
    ref = Process.monitor(ws)
    send ws, {:do_ws_sync_call, args, self, ref}
    receive do
      {:sync_ws_call_reply, ^ref, ret} ->
        Process.demonitor(ref, [:flush])
        ret
      {:DOWN, ^ref, _type, ^ws, _info} -> {:error, :noproc}
    after
      5000 -> {:error, :timeout}
    end
  end

  def send_msg(ws, msg) do
    do_sync_call(ws, {:send_msg, msg})
  end

  def websocket_init(_transport, req, state) do
    {{ip, _port}, req} = Request.peer(req)
    ip = :inet_parse.ntoa(ip)
    Logger.info("Accepted websocket connection (ip=#{ip}) (access_mode=#{state.access_mode})")

    Process.monitor(state.session)

    :ok = Tmate.Session.ws_request_sub(state.session, self)

    start_ping_timer
    {:ok, req, state}
  end

  def websocket_handle({:text, msg}, req, state) do
    handle_ws_msg(state, Poison.decode!(msg))
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

  def websocket_info({:do_ws_sync_call, args, from, ref}, req, state) do
    {:reply, call_ret, ws_ret} = handle_sync_call(args, from, req, state)
    send from, {:sync_ws_call_reply, ref, call_ret}
    ws_ret
  end

  def handle_sync_call({:send_msg, msg}, _from, req, state) do
    {:reply, :ok, {:reply, serialize_msg(msg), req, state}}
  end

  def websocket_terminate(_reason, _req, _state) do
    Logger.info("Closed websocket connection")
    :ok
  end

  def terminate(_reason, _req, _state) do
    :ok
  end

  # TODO validate types
  defp handle_ws_msg(state, [P.tmate_ws_pane_keys, pane_id, data]) do
    :ok = Tmate.Session.send_pane_keys(state.session, pane_id, data)
  end

  defp handle_ws_msg(_state, msg) do
    Logger.warn("Unknown ws msg: #{msg}")
  end

  defp serialize_msg(msg) do
    {:text, Poison.encode_to_iodata!(msg)}
  end
end
