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

  defp verify_auth_token1(%{req_headers: req_headers}, opts) do
    auth_header = Enum.find(req_headers, fn {name, _} -> name == "authorization" end)
    case auth_header do
      {_, "Bearer " <> token} -> Plug.Crypto.secure_compare(token, opts[:auth_token])
      _ -> false
    end
  end

  # old format
  defp verify_auth_token2(%{body_params: %{"auth_key" => token}}, opts) do
    Plug.Crypto.secure_compare(token, opts[:auth_token])
  end
  defp verify_auth_token2(_conn, _opts), do: false

  defp verify_auth_token!(conn, opts) do
    if (!verify_auth_token1(conn, opts) && !verify_auth_token2(conn, opts)) do
      raise Error.Unauthorized
    end
  end
end
