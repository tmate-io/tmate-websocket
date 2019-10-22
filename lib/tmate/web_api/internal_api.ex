defmodule Tmate.WebApi.InternalApi do
  require Logger
  import Plug.Conn

  use Plug.Router
  plug :match

  plug Plug.Parsers, parsers: [:json], json_decoder: Jason

  {:ok, master_options} = Application.fetch_env(:tmate, :master)
  auth_token = master_options[:internal_api][:auth_token]
  plug Tmate.WebApi.PlugVerifyAuthToken, auth_token

  plug :dispatch, builder_opts()


  post "get_stale_sessions" do
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

  match _ do
    send_resp(conn, 404, ":(")
  end
end
