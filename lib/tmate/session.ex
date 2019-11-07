defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P
  alias Tmate.WsApi.WebSocket

  use GenServer
  require Logger

  @max_snapshot_lines 300
  # @latest_version "2.2.1"

  def start_link(session_opts, daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, {session_opts, daemon}, opts)
  end

  def init({session_opts, daemon}) do
    [webhooks: webhooks, registry: registry] = session_opts

    state = %{webhooks: webhooks, registry: registry,
              daemon: daemon, initialized: false,
              ssh_only: false, foreground: false,
              init_state: nil, webhook_pids: [],
              pending_ws_subs: [], ws_subs: [],
              daemon_protocol_version: -1,
              current_layout: [], clients: %{}}

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
    # We must handle EXIT signals that are coming from non parent pids.
    # In this case, we'll let terminate() deal with our cleanup.
    {:stop, reason, state}
  end

  def terminate(reason, %{initialized: true}=state) do
    # Note: the daemon connection and webhooks are linked processes.
    # Any exits different tham :kill from these processes will land us here.
    # We can also get a :stale exit request from the registery.
    # reason is typically:
    # * {:shutdown, :session_fin}: client sent a fin message. Session is closed.
    # * {:shutdown, :tcp_closed}: client disconnected. We can expect a reconnection.
    # * {:shutdown, :stale}: client reconencted, and this session is now stale.

    # We should put the following code in another process that monitors the
    # current process. This way, if the current process crashes, we would
    # still be able to send our disconnect message. But that's more work
    # to implement.
    case reason do
      {:shutdown, :session_fin} -> emit_event(state, :session_close)
      _ -> emit_event(state, :session_disconnect)
    end

    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  def ws_verify_auth(session) do
    GenServer.call(session, {:ws_verify_auth}, :infinity)
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


  def handle_call({:ws_verify_auth}, _from,
                   %{initialized: true, ssh_only: ssh_only}=state) do
    if ssh_only do
      {:reply, {:error, :auth}, state}
    else
      {:reply, :ok, state}
    end
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

  defp emit_event(state, event_type, params \\ %{}) do
    Logger.debug("emit_event: #{event_type}")

    timestamp = DateTime.utc_now
    event = %Tmate.Webhook.Event{type: event_type, entity_id: state.id,
              timestamp: timestamp, generation: state.generation, params: params}

    Tmate.Webhook.Many.emit_event(state.webhooks, state.webhook_pids, event)
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

  defp get_web_url_fmt() do
    user_facing_base_url = Application.get_env(:tmate, :master)[:user_facing_base_url]
    "#{user_facing_base_url}t/%s"
  end

  defp rename_tmux_sockets!(old_stoken, old_stoken_ro, stoken, stoken_ro) do
    {:ok, daemon_options} = Application.fetch_env(:tmate, :daemon)
    t = fn token -> String.replace(token, ["/", "."], "_") end
    p = fn token -> Path.join(daemon_options[:tmux_socket_path], token) end

    old_stoken    = t.(old_stoken)
    old_stoken_ro = t.(old_stoken_ro)
    stoken        = t.(stoken)
    stoken_ro     = t.(stoken_ro)

    if old_stoken != stoken do
      :ok = File.rename(p.(old_stoken), p.(stoken))
    end

    # The ro file is a symlink pointing to the rw socket,
    # so renaming is insufficient
    File.rm(p.(old_stoken_ro))
    File.rm(p.(stoken_ro))
    :ok = File.ln_s(stoken, p.(stoken_ro))
  end

  @max_token_length 50
  @valid_token_regex ~r/^[a-zA-Z0-9-_]+$/

  defp validate_session_token(token) do
    cond do
      !token -> :ok
      String.length(token) == 0 -> {:error, :empty_token}
      String.length(token) > @max_token_length -> {:error, :token_too_long}
      not String.match?(token, @valid_token_regex) -> {:error, :invalid_token}
      true -> :ok
    end
  end

  defp get_named_session_tokens(stoken, stoken_ro,
                     %{account_key: account_key, rw: desired_stoken, ro: desired_stoken_ro, }) do
    cond do
      !desired_stoken && !desired_stoken_ro ->
        {:ok, {stoken, stoken_ro, 1}}
      (err = validate_session_token(desired_stoken)) != :ok ->
        err
      (err = validate_session_token(desired_stoken_ro)) != :ok ->
        err
      desired_stoken == desired_stoken_ro ->
        {:error, :same_tokens}
      !Tmate.MasterApi.enabled? ->
        {:ok, {desired_stoken || stoken, desired_stoken_ro || stoken_ro, 1}}
      !account_key ->
        {:error, :missing_account_key}
      true ->
        case Tmate.MasterApi.get_named_session_tokens(account_key, desired_stoken, desired_stoken_ro) do
          {:ok, {prefixed_stoken, prefixed_stoken_ro, generation}} ->
            {:ok, {prefixed_stoken || stoken, prefixed_stoken_ro || stoken_ro, generation}}
          {:error, :not_found} ->
            {:error, :invalid_account_key}
          {:error, _reason} ->
            {:error, :internal_error}
        end
    end
  end

  defp notify_named_session_error(state, reason) do
    user_facing_base_url = Application.get_env(:tmate, :master)[:user_facing_base_url]
    reg_url = "#{user_facing_base_url}register"
    case reason do
      :emoty_token ->
        notify_daemon(state, "The session name is empty")
      :token_too_long ->
        notify_daemon(state, "The session name length too long (max #{@max_token_length} chars)")
      :invalid_token ->
        notify_daemon(state, "The session name has invalid characters"
                              <> ". Use only alphanumeric, hyphens and underscores")
      :same_tokens ->
        notify_daemon(state, "The same session name for write and read-only access were provided"
                              <> ". Try again with different names")
      :missing_account_key ->
        notify_daemon(state, "To name sessions, specify your account key with -k"
                              <> ". To get an account key, please register at #{reg_url}")
      :invalid_account_key ->
        notify_daemon(state, "The provided account key is invalid. Please fix"
                              <> ". You may reach out for help at help@tmate.io")
      :internal_error ->
        notify_daemon(state, "Temporary server error, tmate will disconnect and reconnect")
        Process.exit(self(), {:shutdown, :master_api_fail})
    end
  end

  defp finalize_session_init(%{init_state: %{ip_address: ip_address, pubkey: pubkey, stoken: stoken,
      stoken_ro: stoken_ro, ssh_cmd_fmt: ssh_cmd_fmt, named_session: named_session,
      client_version: client_version, reconnection_data: reconnection_data,
      user_webhook_opts: user_webhook_opts}, ssh_only: ssh_only, foreground: foreground}=state) do
    old_stoken = stoken
    old_stoken_ro = stoken_ro

    # named sessions
    {stoken, stoken_ro, named_session_error, generation} =
      cond do
        reconnection_data -> {stoken, stoken_ro, nil, 1}
        true ->
          case get_named_session_tokens(stoken, stoken_ro, named_session) do
            {:ok, {rw, ro, gen}} -> {rw, ro, nil, gen}
            {:error, reason} -> {stoken, stoken_ro, reason, 1}
          end
      end

    named = stoken != old_stoken || stoken_ro != old_stoken_ro

    # reconnection
    {reconnected, [id, stoken, stoken_ro, _old_host, generation]} = case reconnection_data do
      nil ->            {false, [UUID.uuid1, stoken, stoken_ro, nil, generation]}
      [2 | rdata_v2] -> {true, rdata_v2}
      rdata_v1 ->       {true, rdata_v1 ++ [2]}
    end
    new_reconnection_data = [2, id, stoken, stoken_ro, Tmate.host, generation+1]

    # socket rename
    if old_stoken != stoken || old_stoken_ro != stoken_ro do
      rename_tmux_sockets!(old_stoken, old_stoken_ro, stoken, stoken_ro)
      send_daemon_msg(state, [P.tmate_ctl_rename_session, stoken, stoken_ro])
    end

    # session registration
    state = Map.merge(state, %{id: id, generation: generation})
    Logger.metadata(session_id: state.id)

    case state.registry do
      {} -> nil
      {registry_mod, registry_pid} ->
        :ok = registry_mod.register_session(registry_pid,
                self(), state.id, stoken, stoken_ro)
    end

    # webhook setup
    state = if user_webhook_opts[:url] do
      Logger.info("User webhook: #{inspect(user_webhook_opts)}")
      %{state | webhooks: state.webhooks ++ [{Tmate.Webhook, user_webhook_opts}]}
    else
      state
    end

    state = %{state | webhook_pids: Tmate.Webhook.Many.start_links(state.webhooks)}

    web_url_fmt = get_web_url_fmt()

    event_payload = %{ip_address: ip_address, pubkey: pubkey, client_version: client_version,
                      stoken: stoken, stoken_ro: stoken_ro, reconnected: reconnected,
                      ssh_only: ssh_only, foreground: foreground, named: named,
                      ssh_cmd_fmt: ssh_cmd_fmt, ws_url_fmt: WebSocket.ws_url_fmt,
                      web_url_fmt: web_url_fmt}

    Logger.info("Session #{if reconnected, do: "reconnected (count=#{generation-1})", else: "started"
                 } (#{stoken |> String.slice(0, 4)}...)")
    emit_event(state, :session_register, event_payload)

    # notifications
    ssh_cmd = String.replace(ssh_cmd_fmt, "%s", stoken)
    ssh_cmd_ro = String.replace(ssh_cmd_fmt, "%s", stoken_ro)

    web_url = String.replace(web_url_fmt, "%s", stoken)
    web_url_ro = String.replace(web_url_fmt, "%s", stoken_ro)

    if !foreground, do: notify_daemon(state, "Note: clear your terminal before sharing readonly access")
    if !ssh_only, do:   notify_daemon(state, "web session read only: #{web_url_ro}")
                        notify_daemon(state, "ssh session read only: #{ssh_cmd_ro}")
    if !ssh_only, do:   notify_daemon(state, "web session: #{web_url}")
                        notify_daemon(state, "ssh session: #{ssh_cmd}")
    if reconnected, do: notify_daemon(state, "Reconnected")

    if named_session_error, do: notify_named_session_error(state, named_session_error)

    if !ssh_only, do: daemon_set_env(state, "tmate_web_ro", web_url_ro)
                      daemon_set_env(state, "tmate_ssh_ro", ssh_cmd_ro)
    if !ssh_only, do: daemon_set_env(state, "tmate_web",    web_url)
                      daemon_set_env(state, "tmate_ssh",    ssh_cmd)

    daemon_set_env(state, "tmate_reconnection_data", pack_and_sign!(new_reconnection_data))

    daemon_send_client_ready(state)

    # maybe_notice_version_upgrade(client_version)

    %{state | initialized: true, init_state: nil}
  end

  # defp maybe_notice_version_upgrade(@latest_version), do: nil
  # defp maybe_notice_version_upgrade(_client_version) do
    # delayed_notify_daemon(20 * 1000, "Your tmate client can be upgraded to #{@latest_version}")
  # end

  defp handle_ctl_msg(%{initialized: false}=state,
                      [P.tmate_ctl_header, 2=_protocol_version, ip_address, pubkey,
                       stoken, stoken_ro, ssh_cmd_fmt, client_version, daemon_protocol_version]) do
    init_state = %{ip_address: ip_address, pubkey: pubkey, stoken: stoken, stoken_ro: stoken_ro,
                   client_version: client_version, ssh_cmd_fmt: ssh_cmd_fmt,
                   named_session: %{rw: nil, ro: nil, account_key: nil},
                   reconnection_data: nil, user_webhook_opts: [url: nil, userdata: ""]}
    state = %{state | daemon_protocol_version: daemon_protocol_version, init_state: init_state}

    if daemon_protocol_version >= 6 do
      # we'll finalize when we get the ready message
      state
    else
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

  defp handle_ctl_msg(state, [P.tmate_ctl_latency, _client_id, _latency]) do
    state
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
    reconnection_data = verify_and_unpack!(reconnection_data)
    %{state | init_state: %{state.init_state | reconnection_data: reconnection_data}}
  end

  defp handle_daemon_msg(state, [P.tmate_out_fin]) do
    Process.exit(self(), {:shutdown, :session_fin})
    state
  end

  defp handle_daemon_msg(state, [P.tmate_out_exec_cmd | args]) do
    handle_daemon_exec_cmd(state, args)
  end

  defp handle_daemon_msg(state, _msg) do
    state
  end

  defp set_webhook_setting(state, key, value) do
    # Due to a bug in tmate client 2.3.0 and lower, we are seing the tmate
    # webhook options after the session is ready (and thus initialization
    # complete). This bug was fixed with commit d654ff22 in tmate client.
    # As a workaround, we kill the connection. When the client reconnects,
    # it provides the webhook configurations before the ready event.
    case state.init_state do
      nil ->
        Logger.debug("Webhook bug workaround: disconnecting client")
        Process.exit(self(), {:shutdown, :bug_webhook})
        state
      init ->
        user_webhook_opts = Keyword.put(init.user_webhook_opts, key, value)
        %{state | init_state: %{init | user_webhook_opts: user_webhook_opts}}
    end
  end

  defp set_named_session_setting(state, key, value) do
    if state.init_state do
      named_session = state.init_state.named_session
      named_session = Map.replace!(named_session, key, value)
      %{state | init_state: %{state.init_state | named_session: named_session}}
    else
      notify_daemon(state, "#{key} can only be set via the command line, or configuration file")
      state
    end
  end

  defp handle_daemon_exec_cmd(state, ["set-option", "-g" | rest]) do
    handle_daemon_exec_cmd(state, ["set-option", rest])
  end

  defp handle_daemon_exec_cmd(state, ["set-option", _key, ""]), do: state # important to filter empty session names
  defp handle_daemon_exec_cmd(state, ["set-option", key, value]) when is_binary(value) do
    case key do
      "tmate-webhook-url"      -> set_webhook_setting(state, :url, value)
      "tmate-webhook-userdata" -> set_webhook_setting(state, :userdata, value)
      "tmate-session-name"     -> set_named_session_setting(state, :rw, value)
      "tmate-session-name-ro"  -> set_named_session_setting(state, :ro, value)
      "tmate-account-key"      -> set_named_session_setting(state, :account_key, value)
      "tmate-authorized-keys"  -> %{state | ssh_only: true}
      "tmate-set" -> case value do
        "authorized_keys=" <> _ssh_key -> %{state | ssh_only: true}
        "foreground=true" -> %{state | foreground: true}
        _ -> state
      end
      _ -> state
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
    for ws <- ws_list, do: WebSocket.send_msg(ws, msg)
  end

  defp send_daemon_msg(state, msg) do
    {transport, handle} = state.daemon
    transport.send_msg(handle, msg)
  end

  # defp delayed_notify_daemon(timeout, msg) do
    # :erlang.start_timer(timeout, self(), {:notify_daemon, msg})
  # end

  defp notify_daemon(state, msg) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_notify, msg]])
  end

  defp daemon_set_env(%{daemon_protocol_version: v}, _, _) when v < 4, do: nil
  defp daemon_set_env(state, key, value) do
    send_daemon_msg(state, [P.tmate_ctl_deamon_fwd_msg,
                             [P.tmate_in_set_env, key, value]])
  end

  defp daemon_send_client_ready(%{daemon_protocol_version: v}) when v < 4, do: nil
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
    client = Map.merge(client, %{id: client_id})

    state = %{state | clients: Map.put(state.clients, ref, client)}
    update_client_presence(state, client, true)
    state
  end

  defp client_left(state, ref) do
    case Map.fetch(state.clients, ref) do
      {:ok, client} ->
        state = %{state | clients: Map.delete(state.clients, ref)}
        update_client_presence(state, client, false)
        state
      :error ->
        Logger.error("Missing client #{inspect(ref)} in client list")
        state
    end
  end

  defp update_client_presence(state, client, join) do
    notify_client_presence_daemon(state, client, join)
    notify_client_presence_webhooks(state, client, join)
  end

  defp notify_client_presence_webhooks(state, client, true) do
    {client_info, _} = Map.split(client, [:id, :type, :ip_address, :identity, :readonly])
    emit_event(state, :session_join, client_info)
  end

  defp notify_client_presence_webhooks(state, client, false) do
    emit_event(state, :session_left, %{id: client.id})
  end

  defp notify_client_presence_daemon(state, client, join) do
    verb = if join, do: 'joined', else: 'left'
    num_clients = Kernel.map_size(state.clients)
    msg = "A mate has #{verb} (#{client.ip_address}) -- " <>
          "#{num_clients} client#{if num_clients > 1, do: 's'} currently connected"
    notify_daemon(state, msg)
  end

  defp update_client_size(state, ref, size) do
    client = Map.fetch!(state.clients, ref)
    client = Map.merge(client, %{size: size})
    state = %{state | clients: Map.put(state.clients, ref, client)}
    recalculate_sizes(state)
    state
  end

  def recalculate_sizes(state) do
    sizes = state.clients
    |> Map.values
    |> Enum.filter(& &1[:size])
    |> Enum.map(& &1[:size])

    {max_cols, max_rows} = if Enum.empty?(sizes) do
      {-1,-1}
    else
      sizes |> Enum.reduce(fn({x,y}, {xx,yy}) -> {Enum.min([x,xx]), Enum.min([y,yy])} end)
    end

    send_daemon_msg(state, [P.tmate_ctl_resize, max_cols, max_rows])
  end

  ##### SSH EXEC #####

  defp human_time(time) do
    {:ok, rel} = Timex.format(time, "{relative}", :relative)
    rel
  end

  defp describe_session(%{disconnected_at: nil, ssh_cmd_fmt: ssh_cmd_fmt}, token) do
    web_url_fmt = get_web_url_fmt()

    ssh_conn = String.replace(ssh_cmd_fmt, "%s", token)
    web_conn = String.replace(web_url_fmt, "%s", token)

    "The session has moved to another server. Use the following to connect:\n" <>
    "web session: #{web_conn}\n" <>
    "ssh session: #{ssh_conn}"
  end

  defp describe_session(%{closed: true, disconnected_at: time}, _token) do
    "This session was closed #{human_time(time)}."
  end

  defp describe_session(%{closed: false, disconnected_at: time}, _token) do
    "The session host disconnected #{human_time(time)}.\n" <>
    "Hopefully it will reconnect soon. You may try again later."
  end

  defp ssh_exec(state, ["explain-session-not-found"], username, _ip_address, _pubkey) do
    token = username

    response = cond do
      Tmate.MasterApi.enabled? -> Tmate.MasterApi.get_session(token)
      true -> {:error, :not_found}
    end |> case do
      {:ok, session} ->
        describe_session(session, token)
      {:error, :not_found} ->
        :timer.sleep(:crypto.rand_uniform(50, 200))
        "Invalid session token"
      {:error, _reason} ->
        :timer.sleep(:crypto.rand_uniform(50, 200))
        "Internal error"
    end
    notify_exec_response(state, 1, response)
  end

  defp ssh_exec(state, _command, _username, _ip_address, _pubkey) do
    notify_exec_response(state, 1, "Invalid command")
  end
end
