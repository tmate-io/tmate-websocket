defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P

  use GenServer
  require Logger

  @max_snapshot_lines 300
  @latest_version "2.2.1"

  def start_link(master, webhook, daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, {master, webhook, daemon}, opts)
  end

  def init({master, webhook, daemon}) do
    state = %{master: master, webhook: webhook, daemon: daemon,
              init_state: nil, webhook_pid: nil, webhook_userdata: nil,
              pending_ws_subs: [], ws_subs: [],
              daemon_protocol_version: -1,
              host_latency: -1, host_latency_stats: Tmate.Stats.new,
              current_layout: [], clients: HashDict.new}

    :ping = master.ping_master
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  def handle_info({:timeout, _ref, {:notify_daemon, msg}}, state) do
    notify_daemon(state, msg)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    {:noreply, handle_ws_disconnect(state, pid)}
  end

  def handle_info({:EXIT, _linked_pid, reason}, state) do
    emit_latency_stats(state, nil, state.host_latency_stats)
    state.clients |> Enum.each(fn {_ref, client} ->
      emit_latency_stats(state, client.id, client.latency_stats)
    end)

    Process.exit(daemon_pid(state), reason)
    if state[:webhook_pid] do
      Process.exit(state.webhook_pid, reason)
    end

    {:stop, reason, state}
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

  def notify_daemon_msg(session, msg) do
    GenServer.call(session, {:notify_daemon_msg, msg}, :infinity)
  end

  def notify_latency(session, client_id, latency) do
    GenServer.call(session, {:notify_latency, client_id, latency})
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
                             [P.tmate_in_exec_cmd_str, client_id, cmd]])
    {:reply, :ok, state}
  end

  def handle_call({:notify_resize, ws, size}, _from, state) do
    {:reply, :ok, update_client_size(state, ws, size)}
  end

  def handle_call({:notify_daemon_msg, msg}, _from, state) do
    {:reply, :ok, handle_ctl_msg(state, msg)}
  end

  def handle_call({:notify_latency, client_id, latency}, _from, state) do
    {:reply, :ok, handle_notify_latency(state, client_id, latency)}
  end

  defp emit_event(state, event_type, params \\ %{}) do
    if state[:webhook_pid] do
      state.webhook.emit_event(state.webhook_pid, event_type, state.id, state[:webhook_userdata], params)
    end
    :ok = state.master.emit_event(event_type, state.id, params)
  end

  def pack_and_sign!(value) do
    {:ok, daemon_options} = Application.fetch_env(:tmate, :daemon)

    value
    |> MessagePack.pack!
    |> (& [&1, :crypto.hmac(:sha256, daemon_options[:hmac_key], &1)]).()
    |> Enum.map(&Base.encode64/1)
    |> Enum.join("|")
  end

  def verify_and_unpack!(value) do
    {:ok, daemon_options} = Application.fetch_env(:tmate, :daemon)

    value
    |> String.split("|")
    |> Enum.map(&Base.decode64!/1)
    |> fn [data, received_signature] ->
      ^received_signature = :crypto.hmac(:sha256, daemon_options[:hmac_key], data)
      data
    end.()
    |> MessagePack.unpack!
  end

  defp rename_tmux_sockets!(old_stoken, old_stoken_ro, stoken, stoken_ro) do
    {:ok, daemon_options} = Application.fetch_env(:tmate, :daemon)
    p = fn filename -> Path.join(daemon_options[:tmux_socket_path], filename) end

    :ok = File.rename(p.(old_stoken), p.(stoken))
    File.rm(p.(old_stoken_ro))
    File.rm(p.(stoken_ro))
    :ok = File.ln_s(stoken, p.(stoken_ro))
  end

  defp setup_webhooks(state, [], _userdata), do: state
  defp setup_webhooks(state, webhook_urls, userdata) do
    {:ok, webhook_pid} = state.webhook.start_link(webhook_urls)
    %{state | webhook_pid: webhook_pid, webhook_userdata: userdata}
  end

  defp finalize_session_init(%{init_state: %{ip_address: ip_address, pubkey: pubkey, stoken: stoken,
      stoken_ro: stoken_ro, ssh_cmd_fmt: ssh_cmd_fmt,
      client_version: client_version, reconnection_data: reconnection_data,
      user_defined_webhook_urls: user_defined_webhook_urls, webhook_userdata: webhook_userdata}}=state) do
    old_stoken = stoken
    old_stoken_ro = stoken_ro

    [reconnected, id, stoken, stoken_ro, old_host] = case reconnection_data do
      nil -> [false, UUID.uuid1, stoken, stoken_ro, nil]
      rdata -> [true | rdata |> verify_and_unpack!]
    end

    if old_stoken != stoken || old_stoken_ro != stoken_ro do
      rename_tmux_sockets!(old_stoken, old_stoken_ro, stoken, stoken_ro)
      send_daemon_msg(state, [P.tmate_ctl_rename_session, stoken, stoken_ro])
    end

    state = Map.merge(state, %{id: id})
    Logger.metadata(session_id: state.id)

    :ok = Tmate.SessionRegistry.register_session(Tmate.SessionRegistry, self, stoken, stoken_ro)

    {:ok, webhook_options} = Application.fetch_env(:tmate, :webhook)
    state = setup_webhooks(state, webhook_options[:urls] ++ user_defined_webhook_urls, webhook_userdata)

    web_url_fmt = Application.get_env(:tmate, :master)[:session_url_fmt]
    event_payload = %{ip_address: ip_address, pubkey: pubkey, client_version: client_version,
                      stoken: stoken, stoken_ro: stoken_ro, reconnected: reconnected,
                      ssh_cmd_fmt: ssh_cmd_fmt, ws_url_fmt: Tmate.WebSocket.ws_url_fmt,
                      web_url_fmt: web_url_fmt}

    Logger.info("Session #{if reconnected, do: "reconnected", else: "started"} (#{stoken})")
    emit_event(state, :session_register, event_payload)

    ssh_cmd = String.replace(ssh_cmd_fmt, "%s", stoken)
    ssh_cmd_ro = String.replace(ssh_cmd_fmt, "%s", stoken_ro)

    web_url = String.replace(web_url_fmt, "%s", stoken)
    web_url_ro = String.replace(web_url_fmt, "%s", stoken_ro)

    if reconnected && old_host != Tmate.host, do: notify_daemon(state, "The session has been reconnected to another server");
    notify_daemon(state, "Note: clear your terminal before sharing readonly access")
    notify_daemon(state, "web session read only: #{web_url_ro}")
    notify_daemon(state, "ssh session read only: #{ssh_cmd_ro}")
    notify_daemon(state, "web session: #{web_url}")
    notify_daemon(state, "ssh session: #{ssh_cmd}")
    if reconnected && old_host == Tmate.host, do: notify_daemon(state, "Reconnected");

    daemon_set_env(state, "tmate_web_ro", web_url_ro)
    daemon_set_env(state, "tmate_ssh_ro", ssh_cmd_ro)
    daemon_set_env(state, "tmate_web",    web_url)
    daemon_set_env(state, "tmate_ssh",    ssh_cmd)

    daemon_set_env(state, "tmate_reconnection_data",
                  [id, stoken, stoken_ro, Tmate.host] |> pack_and_sign!)

    daemon_send_client_ready(state)

    maybe_notice_version_upgrade(client_version)

    %{state | init_state: nil}
  end

  defp maybe_notice_version_upgrade(@latest_version), do: nil
  defp maybe_notice_version_upgrade(_client_version) do
    delayed_notify_daemon(20 * 1000, "Your tmate client can be upgraded to #{@latest_version}")
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_header, 2=_protocol_version, ip_address, pubkey,
                              stoken, stoken_ro, ssh_cmd_fmt,
                              client_version, daemon_protocol_version]) do
    init_state = %{ip_address: ip_address, pubkey: pubkey, stoken: stoken, stoken_ro: stoken_ro,
                   client_version: client_version, ssh_cmd_fmt: ssh_cmd_fmt,
                   reconnection_data: nil, user_defined_webhook_urls: [], webhook_userdata: nil}

    state = %{state | daemon_protocol_version: daemon_protocol_version, init_state: init_state}

    if daemon_protocol_version >= 6 do
      state
    else
      # we'll finalize when we get the ready message
      finalize_session_init(state)
    end
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

  defp handle_ctl_msg(state, [P.tmate_ctl_latency, client_id, latency]) do
    handle_notify_latency(state, client_id, latency)
  end

  defp handle_ctl_msg(state, [P.tmate_ctl_exec, username, ip_address, pubkey, command]) do
    Logger.info("ssh exec: #{inspect(command)} from #{username}@#{ip_address} (#{pubkey})")
    command = String.split(command, " ") |> Enum.filter(& &1 != "")
    ssh_exec(state, command, username, ip_address, pubkey)
    state
  end

  defp handle_ctl_msg(state, msg) do
    Logger.error("Unknown message type=#{inspect(msg)}")
    state
  end

  defp handle_daemon_msg(state, [P.tmate_out_sync_layout | layout]) do
    %{state | current_layout: layout}
  end


  defp handle_daemon_msg(state, [P.tmate_out_ready]) do
    finalize_session_init(state)
  end

  defp handle_daemon_msg(state, [P.tmate_out_reconnect, reconnection_data]) do
    %{state | init_state: %{state.init_state | reconnection_data: reconnection_data}}
  end

  defp handle_daemon_msg(state, [P.tmate_out_fin]) do
    emit_event(state, :session_close)
    Process.exit(self, :normal)
    state
  end

  defp handle_daemon_msg(state, [P.tmate_out_exec_cmd | args]) do
    handle_daemon_exec_cmd(state, args)
  end

  defp handle_daemon_msg(state, _msg) do
    state
  end

  defp handle_daemon_exec_cmd(state, ["set-option", "-g", "tmate-webhook-userdata", webhook_userdata]) do
    %{state | init_state: %{state.init_state | webhook_userdata: webhook_userdata}}
  end

  defp handle_daemon_exec_cmd(state, ["set-option", "-g", "tmate-webhook-url", webhook_url]) do
    {:ok, webhook_options} = Application.fetch_env(:tmate, :webhook)
    if webhook_options[:allow_user_defined_urls] do
      %{state | init_state: %{state.init_state | user_defined_webhook_urls: [webhook_url]}}
    else
      state
    end
  end

  defp handle_daemon_exec_cmd(state, _args) do
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

  defp delayed_notify_daemon(timeout, msg) do
    :erlang.start_timer(timeout, self, {:notify_daemon, msg})
  end

  defp notify_daemon(state, msg) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_notify, msg]])
  end

  defp daemon_set_env(%{daemon_protocol_version: v}, _, _) when v < 4, do: ()
  defp daemon_set_env(state, key, value) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_set_env, key, value]])
  end

  defp daemon_send_client_ready(%{daemon_protocol_version: v}) when v < 4, do: ()
  defp daemon_send_client_ready(state) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_ready]])
  end

  defp notify_exec_response(state, exit_code, msg) do
    msg = ((msg |> String.split("\n")) ++ [""]) |> Enum.join("\r\n")
    send_daemon_msg(state, [P.tmate_ctl_exec_response, exit_code, msg])
  end

  defp client_join(state, ref, client) do
    client_id = UUID.uuid1
    client = Map.merge(client, %{id: client_id, latency_stats: Tmate.Stats.new})

    state = %{state | clients: HashDict.put(state.clients, ref, client)}
    update_client_presence(state, client, true)
    state
  end

  defp client_left(state, ref) do
    case HashDict.fetch(state.clients, ref) do
      {:ok, client} ->
        state = %{state | clients: HashDict.delete(state.clients, ref)}
        update_client_presence(state, client, false)
      :error ->
        Logger.error("Missing client #{inspect(ref)} in client list")
    end
    state
  end

  defp update_client_presence(state, client, join) do
    notify_client_presence_daemon(state, client, join)
    notify_client_presence_master(state, client, join)
  end

  defp notify_client_presence_master(state, client, true) do
    {client_info, _} = Map.split(client, [:id, :type, :ip_address, :identity, :readonly])
    emit_event(state, :session_join, client_info)
  end

  defp notify_client_presence_master(state, client, false) do
    emit_latency_stats(state, client.id, client.latency_stats)
    emit_event(state, :session_left, %{id: client.id})
  end

  defp notify_client_presence_daemon(state, client, join) do
    verb = if join, do: 'joined', else: 'left'
    num_clients = HashDict.size(state.clients)
    msg = "A mate has #{verb} (#{client.ip_address}) -- " <>
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

  def recalculate_sizes(state) do
    sizes = state.clients
    |> HashDict.values
    |> Enum.filter_map(& &1[:size], & &1[:size])

    {max_cols, max_rows} = if Enum.empty?(sizes) do
      {-1,-1}
    else
      sizes |> Enum.reduce(fn({x,y}, {xx,yy}) -> {Enum.min([x,xx]), Enum.min([y,yy])} end)
    end

    send_daemon_msg(state, [P.tmate_ctl_resize, max_cols, max_rows])
  end

  defp handle_notify_latency(state, -1, latency) do
    host_latency_stats = Tmate.Stats.insert(state.host_latency_stats, latency)
    %{state | host_latency: latency, host_latency_stats: host_latency_stats}
  end

  defp handle_notify_latency(state, ref, latency) do
    case state.host_latency do
      -1 -> state
      host_latency ->
        end_to_end_latency = latency + host_latency
        report_end_to_end_latency(state, ref, end_to_end_latency)
    end
  end

  defp report_end_to_end_latency(state, ref, end_to_end_latency) do
    client = HashDict.fetch!(state.clients, ref)
    client = %{client | latency_stats: Tmate.Stats.insert(client.latency_stats, end_to_end_latency)}
    state = %{state | clients: HashDict.put(state.clients, ref, client)}

    end_to_end_latency
    |> ExStatsD.timer("#{Tmate.host}.end_to_end_latency")
    |> ExStatsD.timer("end_to_end_latency")
    state
  end

  defp emit_latency_stats(state, client_id, stats) do
    if Tmate.Stats.has_stats?(stats) do
      latency_stats = [:n, :mean, :stddev, :median, :p90, :p99]
        |> Enum.reduce(%{}, fn f, acc -> Map.put(acc, f, apply(Tmate.Stats, f, [stats])) end)
      emit_event(state, :session_stats, %{id: client_id, latency: latency_stats})
    end
    :ok
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
