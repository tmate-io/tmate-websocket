defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P
  use GenServer
  require Logger

  def start_link(daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, daemon, opts)
  end

  def init(daemon) do
    Process.monitor(daemon)
    {:ok, ws_event_manager} = GenEvent.start_link()
    {:ok, %{daemon: daemon, ws_event_manager: ws_event_manager, pending_ws_subs: [],
            daemon_protocol_version: -1, current_layout: []}}
  end

  def handle_info({:DOWN, _ref, _type, _pid, _info}, state) do
    Logger.info("Session finished")
    {:stop, :normal, state}
  end

  def handle_daemon_msg(session, msg) do
    GenServer.call(session, {:handle_daemon_msg, msg})
  end

  def ws_request_sub(session, ws) do
    GenServer.call(session, {:ws_request_sub, ws})
  end

  def handle_call({:ws_request_sub, ws}, _from, state) do
    # We'll queue up the subscribers until we get the snapshot
    # so they can get a consistent stream.
    :ok = send_msg(state, [P.tmate_ctl_request_snapshot])
    {:reply, :ok, %{state | pending_ws_subs: [ws | state.pending_ws_subs]}}
  end

  def handle_call({:handle_daemon_msg, msg}, _from, state) do
    {:reply, :ok, receive_ctl_msg(state, msg)}
  end

  defp receive_ctl_msg(state, [P.tmate_ctl_auth, _protocol_version, _ip_address, _pubkey,
                               session_token, session_token_ro]) do
    Logger.metadata([session_token: session_token])
    Logger.info("Session started")

    :ok = Tmate.SessionRegistery.register_session(
            Tmate.SessionRegistery, self, session_token, session_token_ro)
    Map.merge(state, %{session_token: session_token})
  end

  defp receive_ctl_msg(state, msg = [P.tmate_ctl_deamon_out_msg, dmsg]) do
    GenEvent.ack_notify(state.ws_event_manager, msg)
    receive_daemon_msg(state, dmsg)
  end

  defp receive_ctl_msg(state, snapshot_msg = [P.tmate_ctl_snapshot | _]) do
    layout_msg = [P.tmate_ctl_deamon_out_msg, [P.tmate_out_sync_layout, state.current_layout]]
    state.pending_ws_subs |> Enum.each fn(ws) ->
      # we don't care if we fail: the websocket might have disconnected.
      # Note: this call is synchronous nevertheless, so we don't send events
      # through the event manager until the websocket has registered its event callback.
      Tmate.WebSocketEvent.subscribe(ws, state.ws_event_manager)
      Tmate.WebSocketEvent.send_msg(ws, layout_msg)
      Tmate.WebSocketEvent.send_msg(ws, snapshot_msg)
    end
    %{state | pending_ws_subs: []}
  end

  defp receive_ctl_msg(state, [cmd | _]) do
    Logger.warn("Unknown message type=#{cmd}")
    state
  end

  defp receive_daemon_msg(state, [P.tmate_out_header, protocol_version,
                                  _client_version_string]) do
    %{state | daemon_protocol_version: protocol_version}
  end

  defp receive_daemon_msg(state, [P.tmate_out_sync_layout | layout]) do
    %{state | current_layout: layout}
  end

  defp receive_daemon_msg(state, _msg) do
    # TODO
    state
  end

  defp send_msg(state, msg) do
    Tmate.DaemonTcp.send_msg(state.daemon, msg)
  end
end
