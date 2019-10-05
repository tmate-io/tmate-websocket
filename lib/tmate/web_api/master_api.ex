defmodule Tmate.WebApi.MasterApi do
  require Logger
  import Plug.Conn

  def report_active_sessions(%{body_params: %{"sessions" => session_ids}}=conn, opts)
                            when is_list(session_ids) do
    {registry_mod, registry_pid} = opts[:registry]

    stale_ids = Enum.flat_map(session_ids, fn id ->
      case registry_mod.get_session_by_id(registry_pid, id) do
        :error -> [id]
        _ -> []
      end
    end)
    prune_master_sessions(stale_ids, opts)

    send_resp(conn, 200, "{}")
  end

  defp prune_master_sessions([], _opts), do: nil
  defp prune_master_sessions(session_ids, opts) do
    webhooks = opts[:webhooks]

    pids = Tmate.Webhook.Many.start_links(webhooks)

    timestamp = DateTime.utc_now
    Enum.each(session_ids, fn id ->
      Tmate.Webhook.Many.emit_event(webhooks, pids,
        :session_disconnect, id, timestamp, %{}, max_attempts: 1)
    end)

    # No need to manually kill the webhooks. They trap exits.
  end
end
