defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P
  use GenServer
  require Logger

  @max_snapshot_lines 1000

  def start_link(daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, daemon, opts)
  end

  def init(daemon) do
    Process.monitor(daemon)
    {:ok, %{daemon: daemon, pending_ws_subs: [], ws_subs: [],
            daemon_protocol_version: -1, current_layout: []}}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    if state.daemon == pid do
        Logger.info("Session finished")
        {:stop, :normal, state}
    else
      {:noreply, %{state | pending_ws_subs: state.pending_ws_subs -- [pid],
                           ws_subs: state.ws_subs -- [pid]}}
    end
  end

  def notify_daemon_msg(session, msg) do
    GenServer.call(session, {:notify_daemon_msg, msg})
  end

  def ws_request_sub(session, ws) do
    GenServer.call(session, {:ws_request_sub, ws})
  end

  def send_pane_keys(session, pane_id, data) do
    GenServer.call(session, {:send_pane_keys, pane_id, data})
  end

  def handle_call({:ws_request_sub, ws}, _from, state) do
    # We'll queue up the subscribers until we get the snapshot
    # so they can get a consistent stream.
    send_daemon_msg(state, [P.tmate_ctl_request_snapshot, @max_snapshot_lines])
    Process.monitor(ws)
    {:reply, :ok, %{state | pending_ws_subs: [ws | state.pending_ws_subs]}}
  end

  def handle_call({:send_pane_keys, pane_id, data}, _from, state) do
    send_daemon_msg(state, [P.tmate_ctl_pane_keys, pane_id, data])
    {:reply, :ok, state}
  end

  def handle_call({:notify_daemon_msg, msg}, _from, state) do
    {:reply, :ok, handle_ctl_msg(state, msg)}
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_auth, _protocol_version, _ip_address, _pubkey,
                               session_token, session_token_ro]) do
    Logger.metadata([session_token: session_token])
    Logger.info("Session started")

    :ok = Tmate.SessionRegistery.register_session(
            Tmate.SessionRegistery, self, session_token, session_token_ro)
    Map.merge(state, %{session_token: session_token})
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_deamon_out_msg, dmsg]) do
    # TODO serialize once, and then send to all clients.
    for ws <- state.ws_subs, do: send_ws_msg(ws, [P.tmate_ws_daemon_out_msg, dmsg])
    handle_daemon_msg(state, dmsg)
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_snapshot, smsg]) do
    for ws <- state.pending_ws_subs do
      send_ws_msg(ws, [P.tmate_ws_daemon_out_msg, [P.tmate_out_sync_layout | state.current_layout]])
      send_ws_msg(ws, [P.tmate_ws_snapshot, smsg])
    end
    %{state | pending_ws_subs: [], ws_subs: state.ws_subs ++ state.pending_ws_subs}
  end

  defp handle_ctl_msg(state, [cmd | _]) do
    Logger.warn("Unknown message type=#{cmd}")
    state
  end

  defp handle_daemon_msg(state, [P.tmate_out_header, protocol_version,
                                  _client_version_string]) do
    %{state | daemon_protocol_version: protocol_version}
  end

  defp handle_daemon_msg(state, [P.tmate_out_sync_layout | layout]) do
    %{state | current_layout: layout}
  end

  defp handle_daemon_msg(state, _msg) do
    # TODO
    state
  end

  defp send_ws_msg(ws, msg) do
    # TODO we'll need a better buffering strategy.
    # For now the websocket timeout is set to 1000 to avoid
    # problems with having the daemon being slow
    case Tmate.WebSocket.send_msg(ws, msg) do
      :ok -> :ok
      {:error, :timeout} ->
        :erlang.exit(ws, :kill)
        Logger.error("websocket is taking too long. killing")
      {:error, :noproc} ->
    end
  end

  defp send_daemon_msg(state, msg) do
    Tmate.DaemonTcp.send_msg(state.daemon, msg)
  end
end
