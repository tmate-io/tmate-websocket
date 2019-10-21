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

  defp ensure_internal_api_auth!(%{body_params: %{"auth_key" => auth_token}}) do
    {:ok, master_options} = Application.fetch_env(:tmate, :master)
    needed_auth_token = master_options[:internal_api][:auth_token]
    if !Plug.Crypto.secure_compare(auth_token, needed_auth_token) do
      raise Error.Unauthorized
    end
  end
  defp ensure_internal_api_auth!(_), do: raise Error.Unauthorized

  # TODO take out
  post "/master_api/get_stale_sessions" do
    ensure_internal_api_auth!(conn)
    Tmate.WebApi.InternalApi.get_stale_sessions(conn, opts)
  end

  post "/internal_api/get_stale_sessions" do
    ensure_internal_api_auth!(conn)
    Tmate.WebApi.InternalApi.get_stale_sessions(conn, opts)
  end

  # get "/ws/session/:stoken" is defined at the top

  get "/" do
    {:ok, master_options} = Application.fetch_env(:tmate, :master)
    url = master_options[:user_facing_base_url]
    html = Plug.HTML.html_escape(url)
    body = "<html><body>You are being <a href=\"#{html}\">redirected</a>.</body></html>"

    conn
    |> put_resp_header("location", url)
    |> send_resp(302, body)
  end

  match _ do
    send_resp(conn, 404, ":(")
  end
end
