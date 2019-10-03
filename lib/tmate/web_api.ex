defmodule Tmate.WebApi do
  require Logger
  use Plug.Router
  use Plug.ErrorHandler

  def cowboy_dispatch do
    :cowboy_router.compile([{:_, [
      {"/ws/session/:stoken", Tmate.WebSocket, []},
      {:_, Plug.Cowboy.Handler, {__MODULE__, [webhook_mod: Tmate.Webhook]}},
    ]}])
  end

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug Plug.Logger, log: :debug
  plug :dispatch, builder_opts()

  defmodule AuthError do
    defexception message: "Forbidden", plug_status: 403
  end

  post "/master_api/report_active_sessions" do
    ensure_master_auth!(conn.body_params)
    case report_active_sessions(conn.body_params, opts) do
      :error -> send_resp(conn, 503, '{"error": "webhook failed"}')
      :ok    -> send_resp(conn, 200, "{}")
    end
  end

  defp ensure_master_auth!(%{"auth_key" => auth_key}) do
    {:ok, ws_options} = Application.fetch_env(:tmate, :websocket)
    if !Plug.Crypto.secure_compare(auth_key, ws_options[:wsapi_key]) do
      raise AuthError
    end
  end
  defp ensure_master_auth!(_), do: raise AuthError

  defp report_active_sessions(%{"sessions" => session_ids}, opts) when is_list(session_ids) do
    stale_ids = Enum.flat_map(session_ids, fn id ->
      case Tmate.SessionRegistry.get_session_by_id(Tmate.SessionRegistry, id) do
        :error -> [id]
        _ -> []
      end
    end)
    prune_master_sessions(stale_ids, opts)
  end

  defp prune_master_sessions([], _opts), do: nil
  defp prune_master_sessions(session_ids, opts) do
    timestamp = DateTime.utc_now
    webhook_mod = opts[:webhook_mod]

    {:ok, webhook_options} = Application.fetch_env(:tmate, :webhook)
    results = Enum.flat_map(webhook_options[:webhooks], fn webhook ->
      Enum.map(session_ids, fn id ->
        webhook_mod.emit_event_sync(webhook, :session_disconnect, id, timestamp)
      end)
    end)

    if Enum.any?(results, & &1 == :error), do: :error, else: :ok
  end

  match _ do
    send_resp(conn, 404, ":(")
  end
end
