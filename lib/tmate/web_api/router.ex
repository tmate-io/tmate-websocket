defmodule Tmate.WebApi.Router do
  use Plug.Router
  use Plug.ErrorHandler

  def cowboy_dispatch(session_opts) do
    :cowboy_router.compile([{:_, [
      {"/ws/session/:stoken", Tmate.WebApi.WebSocket, []},
      {:_, Plug.Cowboy.Handler, {__MODULE__, session_opts}},
    ]}])
  end

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug Plug.Logger, log: :debug
  plug :dispatch, builder_opts()

  defmodule Error.Unauthorized do
    defexception message: "Unauthorized", plug_status: 401
  end

  defp ensure_master_auth!(%{body_params: %{"auth_key" => auth_key}}) do
    {:ok, ws_options} = Application.fetch_env(:tmate, :websocket)
    if !Plug.Crypto.secure_compare(auth_key, ws_options[:wsapi_key]) do
      raise Error.Unauthorized
    end
  end
  defp ensure_master_auth!(_), do: raise Error.Unauthorized

  post "/master_api/report_active_sessions" do
    ensure_master_auth!(conn)
    Tmate.WebApi.MasterApi.report_active_sessions(conn, opts)
  end

  match _ do
    send_resp(conn, 404, ":(")
  end
end
