defmodule Tmate.WebApi.InternalApi do
  require Logger
  import Plug.Conn

  def get_stale_sessions(conn, opts) do
    stale_ids = get_stale_sessions_stub(conn.body_params, opts)
    json(conn, 200, %{stale_ids: stale_ids})
  end

  defp get_stale_sessions_stub(%{"session_ids" => session_ids}, opts)
                                when is_list(session_ids) do
    {registry_mod, registry_pid} = opts[:registry]
    Enum.flat_map(session_ids, fn id ->
      case registry_mod.get_session_by_id(registry_pid, id) do
        :error -> [id]
        _ -> []
      end
    end)
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
