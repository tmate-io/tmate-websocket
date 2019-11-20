defmodule Tmate.WsApi.Router do
  use Plug.Router
  use Plug.ErrorHandler

  def cowboy_dispatch(session_opts) do
    :cowboy_router.compile([{:_, [
      {"/ws/session/[...]", Tmate.WsApi.WebSocket, []},
      {:_, Plug.Cowboy.Handler, {__MODULE__, session_opts}},
    ]}])
  end

  plug :match
  plug Plug.Logger, log: :debug
  plug :dispatch, builder_opts()

  match "/internal_api/*glob" do
    Plug.Router.Utils.forward(conn, ["internal_api"], Tmate.WsApi.InternalApi, opts)
  end

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
