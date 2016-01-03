defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P

  use GenServer
  require Logger

  @max_snapshot_lines 300

  def start_link(master, daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, {master, daemon}, opts)
  end

  def init({master, daemon}) do
    :ping = Tmate.MasterEndpoint.ping_master

    state = %{master: master, daemon: daemon,
              id: UUID.uuid1(),
              pending_ws_subs: [], ws_subs: [],
              slave_protocol_version: -1, daemon_protocol_version: -1,
              current_layout: [], clients: HashDict.new, next_client_id: 0}
    Logger.metadata(session_id: state.id)
    Process.monitor(daemon_pid(state))
    {:ok, state}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    if daemon_pid(state) == pid do
      {:stop, :normal, state}
    else
      {:noreply, handle_ws_disconnect(state, pid)}
    end
  end

  def notify_daemon_msg(session, msg) do
    GenServer.call(session, {:notify_daemon_msg, msg}, :infinity)
  end

  def ws_request_sub(session, ws, client) do
    GenServer.call(session, {:ws_request_sub, ws, client}, :infinity)
  end

  def send_pane_keys(session, pane_id, data) do
    GenServer.call(session, {:send_pane_keys, pane_id, data}, :infinity)
  end

  def send_exec_cmd(session, client_id, cmd) do
    GenServer.call(session, {:send_exec_cmd, client_id, cmd}, :infinity)
  end

  def notify_resize(session, ws, size) do
    GenServer.call(session, {:notify_resize, ws, size}, :infinity)
  end

  def handle_call({:ws_request_sub, ws, client}, _from, state) do
    # We'll queue up the subscribers until we get the snapshot
    # so they can get a consistent stream.
    state = client_join(state, ws, client)
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

  def handle_call({:notify_resize, ws, size}, _from, state) do
    {:reply, :ok, update_client_size(state, ws, size)}
  end

  def handle_call({:notify_daemon_msg, msg}, _from, state) do
    {:reply, :ok, handle_ctl_msg(state, msg)}
  end

  defp watch_session_close(state) do
    current = self
    master = state.master
    id = state.id

    _pid = spawn fn ->
      ref = Process.monitor(current)
      receive do
        {:DOWN, ^ref, _type, _pid, _info} ->
          :ok = master.emit_event(:session_close, id)
      end
    end
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_auth, protocol_version, ip_address, pubkey,
                              stoken, stoken_ro]) do
    :ok = Tmate.SessionRegistry.register_session(
            Tmate.SessionRegistry, self, stoken, stoken_ro)

    :ok = state.master.emit_event(:session_register, state.id,
                                  %{ip_address: ip_address, pubkey: pubkey,
                                    ws_base_url: Tmate.WebSocket.ws_base_url,
                                    stoken: stoken, stoken_ro: stoken_ro})
    watch_session_close(state)

    Logger.metadata([sid: state.id])
    Logger.info("Session started (#{stoken})")

    %{state | slave_protocol_version: protocol_version}
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

  defp handle_ctl_msg(state, [P.tmate_ctl_client_join, client_id, ip_address, pubkey, readonly]) do
    client_join(state, client_id, %{type: :ssh, ip_address: ip_address,
                                    identity: pubkey, readonly: readonly})
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_client_left, client_id]) do
    client_left(state, client_id)
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_exec, username, ip_address, pubkey, command]) do
    Logger.info("ssh exec: #{inspect(command)} from #{username}@#{ip_address} (#{pubkey})")
    command = String.split(command, " ") |> Enum.filter(& &1 != "")
    ssh_exec(state, command, username, ip_address, pubkey)
    state
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

  defp handle_ws_disconnect(state, ws) do
    state = client_left(state, ws)
    recalculate_sizes(state)
    %{state | pending_ws_subs: state.pending_ws_subs -- [ws],
              ws_subs: state.ws_subs -- [ws]}
  end

  defp ws_broadcast_msg(ws_list, msg) do
    # TODO we'll need a better buffering strategy
    # Right now we are sending async messages, with no back pressure.
    # This might be problematic.
    # TODO We might want to serialize the msg here to avoid doing it N times.
    for ws <- ws_list, do: Tmate.WebSocket.send_msg(ws, msg)
  end

  defp daemon_pid(state) do
    {transport, handle} = state.daemon
    transport.daemon_pid(handle)
  end

  defp send_daemon_msg(state, msg) do
    {transport, handle} = state.daemon
    transport.send_msg(handle, msg)
  end

  defp notify_daemon(state, msg) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_notify, msg]])
  end

  defp notify_exec_response(state, exit_code, msg) do
    msg = ((msg |> String.split("\n")) ++ [""]) |> Enum.join("\r\n")
    send_daemon_msg(state, [P.tmate_ctl_exec_response, exit_code, msg])
  end

  defp client_join(state, ref, client) do
    client_id = state.next_client_id
    state = %{state | next_client_id: client_id + 1}
    client = Map.merge(client, %{id: client_id})

    state = %{state | clients: HashDict.put(state.clients, ref, client)}
    update_client_presence(state, client, true)
    state
  end

  defp client_left(state, ref) do
    client = HashDict.fetch!(state.clients, ref)
    state = %{state | clients: HashDict.delete(state.clients, ref)}
    update_client_presence(state, client, false)
    state
  end

  defp update_client_presence(state, client, join) do
    notify_client_presence_daemon(state, client, join)
    notify_client_presence_master(state, client, join)
  end

  defp notify_client_presence_master(state, client, true) do
    {client_info, _} = Map.split(client, [:id, :type, :ip_address, :identity, :readonly])
    :ok = state.master.emit_event(:session_join, state.id, client_info)
  end

  defp notify_client_presence_master(state, client, false) do
    :ok = state.master.emit_event(:session_left, state.id, %{id: client[:id]})
  end

  defp notify_client_presence_daemon(state, client, join) do
    verb = if join, do: 'joined', else: 'left'
    num_clients = HashDict.size(state.clients)
    msg = "A mate has #{verb} (#{client[:ip_address]}) -- " <>
          "#{num_clients} client#{if num_clients > 1, do: 's'} currently connected"
    notify_daemon(state, msg)
  end

  defp update_client_size(state, ref, size) do
    client = HashDict.fetch!(state.clients, ref)
    client = Map.merge(client, %{size: size})
    state = %{state | clients: HashDict.put(state.clients, ref, client)}
    recalculate_sizes(state)
    state
  end

  defp recalculate_sizes(state) do
    {max_cols, max_rows} = if Enum.empty?(state.clients) do
      {-1,-1}
    else
      state.clients
        |> HashDict.values
        |> Enum.filter_map(& &1[:size], & &1[:size])
        |> Enum.reduce(fn({x,y}, {xx,yy}) -> {Enum.min([x,xx]), Enum.min([y,yy])} end)
    end
    send_daemon_msg(state, [P.tmate_ctl_resize, max_cols, max_rows])
  end

  defp ssh_exec(state, ["identify", token], username, ip_address, pubkey) do
    case state.master.identify_client(token, username, ip_address, pubkey) do
      {:ok, message} -> notify_exec_response(state, 0, message)
      {:error, reason} ->
        notify_exec_response(state, 1, "Internal error")
        raise reason
    end
  end

  defp ssh_exec(state, _command, _username, _ip_address, _pubkey) do
    notify_exec_response(state, 1, "Invalid command")
  end
end
