defmodule Tmate.WebSocket do
  require Logger
  require Tmate.ProtocolDefs, as: P

  alias :cowboy_req, as: Request

  @ping_interval_sec 30

  def cowboy_dispatch do
    :cowboy_router.compile([{:_, [
      {"/ws/session/:stoken", __MODULE__, []},
    ]}])
  end

  def init({_transport, :http}, req, _opts) do
    {stoken, req} = Request.binding(:stoken, req)
    Logger.metadata([stoken: stoken])

    # TODO Check the request origin

    # TODO monads?
    case identity = get_identity(req) do
      nil -> {:ok, req, [401, [], "Cookie not found?"]}
      _ ->
        case Tmate.SessionRegistry.get_session(Tmate.SessionRegistry, stoken) do
          {mode, session} -> {:upgrade, :protocol, :cowboy_websocket, req,
                              %{session: session, access_mode: mode, identity: identity}}
          :error -> {:ok, req, [404, [], "Session not found"]}
        end
    end
  end

  defp get_identity(_req) do
    UUID.uuid1()
  end

  # defp get_identity(req) do
    # {:ok, websocket_options} = Application.fetch_env(:tmate, :websocket)
    # opts = websocket_options[:cookie_opts]

    # store = Plug.Session.COOKIE
    # store_opts = store.init(opts)
    # store_opts = %{store_opts | key_opts: Keyword.put(store_opts.key_opts, :cache, nil)}
    # conn = %{secret_key_base: opts[:secret_key_base]}

    # {cookie, _} = Request.cookie(opts[:key], req)
    # case cookie do
      # :undefined -> nil
      # _ ->
        # {:term, %{"identity" => identity}} = store.get(conn, cookie, store_opts)
        # identity
    # end
  # end

  def ws_url_fmt do
    {:ok, ws_env} = Application.fetch_env(:tmate, :websocket)
    ssl = ws_env[:listener] == :ranch_ssl
    host = ws_env[:host] || Node.self |> to_string |> String.split("@") |> Enum.at(1)
    default_port = if ssl, do: 443, else: 80
    port = if ws_env[:ranch_opts][:port] == default_port, do: "", else: ":#{ws_env[:ranch_opts][:port]}"
    schema = if ssl, do: "wss", else: "ws"
    "#{schema}://#{host}#{port}/ws/session/%s"
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
    ip = :inet_parse.ntoa(ip) |> to_string
    Logger.info("Accepted websocket connection (ip=#{ip}) (access_mode=#{state.access_mode})")

    Process.monitor(state.session)

    client_info = %{type: :web, identity: state.identity, ip_address: ip,
                    readonly: [ro: true, rw: false][state.access_mode]}
    :ok = Tmate.Session.ws_request_sub(state.session, self, client_info)

    start_ping_timer(5000)
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
    latency = :erlang.monotonic_time(:milli_seconds) - state.last_ping_at
    Tmate.Session.notify_latency(state.session, self, latency)
    {:ok, req, state}
  end

  def websocket_handle(_, req, state) do
    {:ok, req, state}
  end

  defp start_ping_timer(timeout \\ @ping_interval_sec * 1000) do
    :erlang.start_timer(timeout, self, :ping)
  end

  def websocket_info({:timeout, _ref, :ping}, req, state) do
    start_ping_timer
    state = Map.merge(state, %{last_ping_at: :erlang.monotonic_time(:milli_seconds)})
    {:reply, :ping, req, state}
  end

  def websocket_info({:DOWN, _ref, _type, _pid, _info}, req, state) do
    {:reply, :close, req, state}
  end

  def websocket_info({:send_msg, msg}, req, state) do
     {:reply, serialize_msg!(msg), req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
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
