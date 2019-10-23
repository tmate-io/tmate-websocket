defmodule Tmate.WebApi.PlugVerifyAuthToken do
  @behaviour Plug

  defmodule Error.Unauthorized do
    defexception message: "Unauthorized", plug_status: 401
  end

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    opts = if is_function(opts), do: opts.(), else: opts
    verify_auth_token!(conn, opts)
    conn
  end

  defp verify_auth_token(%{req_headers: req_headers}, opts) do
    auth_header = Enum.find(req_headers, fn {name, _} -> name == "authorization" end)
    case auth_header do
      {_, "Bearer " <> token} -> Plug.Crypto.secure_compare(token, opts[:auth_token])
      _ -> false
    end
  end

  defp verify_auth_token!(conn, opts) do
    if (!verify_auth_token(conn, opts)), do: raise Error.Unauthorized
  end
end
