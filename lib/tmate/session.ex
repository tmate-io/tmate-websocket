defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P
  alias Tmate.DaemonTcp, as: Daemon

  use GenServer
  require Logger


  @max_snapshot_lines 300

  def start_link(daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, daemon, opts)
  end

  def init(daemon) do
    Process.monitor(Daemon.daemon_pid(daemon))
    {:ok, %{daemon: daemon, pending_ws_subs: [], ws_subs: [],
            daemon_protocol_version: -1, current_layout: [],
            clients: HashDict.new}}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    if Daemon.daemon_pid(state.daemon) == pid do
        {:stop, :normal, state}
    else
      state = client_left(state, pid)
      {:noreply, %{state | pending_ws_subs: state.pending_ws_subs -- [pid],
                           ws_subs: state.ws_subs -- [pid]}}
    end
  end

  def notify_daemon_msg(session, msg) do
    GenServer.call(session, {:notify_daemon_msg, msg}, :infinity)
  end

  def ws_request_sub(session, ws, client_info) do
    GenServer.call(session, {:ws_request_sub, ws, client_info}, :infinity)
  end

  def send_pane_keys(session, pane_id, data) do
    GenServer.call(session, {:send_pane_keys, pane_id, data}, :infinity)
  end

  def send_exec_cmd(session, client_id, cmd) do
    GenServer.call(session, {:send_exec_cmd, client_id, cmd}, :infinity)
  end

  def notify_resize(session, max_cols, max_rows) do
    GenServer.call(session, {:notify_resize, max_cols, max_rows}, :infinity)
  end

  def handle_call({:ws_request_sub, ws, client_info}, _from, state) do
    # We'll queue up the subscribers until we get the snapshot
    # so they can get a consistent stream.
    state = client_joined(state, ws, client_info)
    Process.monitor(ws)
    send_daemon_msg(state, [P.tmate_ctl_request_snapshot, @max_snapshot_lines])
    {:reply, :ok, %{state | pending_ws_subs: state.pending_ws_subs ++ [ws]}}
  end

  def handle_call({:send_pane_keys, pane_id, data}, _from, state) do
    send_daemon_msg(state, [P.tmate_ctl_pane_keys, pane_id, data])
    {:reply, :ok, state}
  end

  def handle_call({:send_exec_cmd, client_id, cmd}, _from, state) do
    Logger.debug("Sending exec: #{cmd}")
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_exec_cmd, client_id, cmd]])
    {:reply, :ok, state}
  end

  def handle_call({:notify_resize, max_cols, max_rows}, from, state) do
    # TODO
    {:reply, :ok, state}
  end

  def handle_call({:notify_daemon_msg, msg}, _from, state) do
    {:reply, :ok, handle_ctl_msg(state, msg)}
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_auth, _protocol_version, _ip_address, _pubkey,
                               session_token, session_token_ro]) do
    Logger.metadata([session_token: session_token])
    Logger.info("Session started")

    :ok = Tmate.SessionRegistry.register_session(
            Tmate.SessionRegistry, self, session_token, session_token_ro)
    Map.merge(state, %{session_token: session_token})
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_deamon_out_msg, dmsg]) do
    ws_broadcast_msg(state.ws_subs, [P.tmate_ws_daemon_out_msg, dmsg])
    handle_daemon_msg(state, dmsg)
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_snapshot, smsg]) do
    layout_msg = [P.tmate_ws_daemon_out_msg, [P.tmate_out_sync_layout | state.current_layout]]
    snapshot_msg = [P.tmate_ws_snapshot, smsg]

    ws_broadcast_msg(state.pending_ws_subs, layout_msg)
    ws_broadcast_msg(state.pending_ws_subs, snapshot_msg)

    %{state | pending_ws_subs: [], ws_subs: state.ws_subs ++ state.pending_ws_subs}
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_client_join, client_id, ip_address, pubkey]) do
    client_joined(state, client_id, [ip_address: ip_address, pubkey: pubkey])
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_client_left, client_id]) do
    client_left(state, client_id)
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

  defp ws_broadcast_msg(ws_list, msg) do
    # TODO we'll need a better buffering strategy
    # Right now we are sending async messages, with no back pressure.
    # This might be problematic.
    # We might want to serialize the msg here to avoid doing it N times.
    for ws <- ws_list, do: Tmate.WebSocket.send_msg(ws, msg)
  end

  defp send_daemon_msg(state, msg) do
    Tmate.DaemonTcp.send_msg(state.daemon, msg)
  end

  defp notify_daemon(state, msg) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_notify, msg]])
  end

  defp client_joined(state, id, client_info) do
    state = %{state | clients: HashDict.put(state.clients, id, client_info)}
    notify_clients_change(state, client_info, true)
    state
  end

  defp client_left(state, id) do
    client_info = HashDict.fetch!(state.clients, id)
    state = %{state | clients: HashDict.delete(state.clients, id)}
    notify_clients_change(state, client_info, false)
    state
  end

  defp notify_clients_change(state, client_info, join) do
    verb = if join, do: 'joined', else: 'left'
    num_clients = HashDict.size(state.clients)
    msg = "A mate has #{verb} (#{client_info[:ip_address]}) -- " <>
          "#{num_clients} client#{if num_clients > 1, do: 's'} currently connected"
    notify_daemon(state, msg)
  end
end
