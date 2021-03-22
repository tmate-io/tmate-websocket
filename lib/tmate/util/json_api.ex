defmodule Tmate.Util.JsonApi do
  defmacro __using__(opts) do
    quote do
      import Tmate.Util.JsonApi
      use HTTPoison.Base
      alias HTTPoison.Request
      alias HTTPoison.Response
      alias HTTPoison.Error
      require Logger

      @opts unquote(opts[:fn_opts])

      defp opts() do
        if is_function(@opts), do: @opts.(), else: @opts
      end

      def process_url(url) do
        base_url = opts()[:base_url]
        if base_url, do: base_url <> url, else: url
      end

      def process_request_headers(headers) do
        auth_token = opts()[:auth_token]
        auth_headers = if auth_token, do: [{"Authorization", "Bearer " <> auth_token}], else: []
        json_headers =  [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
        headers ++ auth_headers ++ json_headers
      end

      def process_request_body(""), do: ""
      def process_request_body(body) do
        Jason.encode!(body)
      end

      def process_response(%Response{headers: headers, body: body} = response) do
        content_type_hdr = Enum.find(headers, fn {name, _} -> String.downcase(name) == "content-type" end)
        body = case content_type_hdr do
          {_, "application/json" <> _} -> Jason.decode!(body)
          _ -> body
        end

        %{response | body: body}
      end

      defp simplify_response({:ok, %Response{status_code: 200, body: body}}, _) do
        {:ok, body}
      end

      defp simplify_response({:ok, %Response{status_code: status_code}},
                              %Request{url: url, method: method}) do
        Logger.error("API error: #{method} #{url} [#{status_code}]")
        {:error, status_code}
      end

      defp simplify_response({:error, %Error{reason: reason}},
                              %Request{url: url, method: method}) do
        Logger.error("API error: #{method} #{url} [#{reason}]")
        {:error, reason}
      end

      defp debug_response({:ok, %Response{status_code: status_code, body: resp_body}} = response,
                           %Request{url: url, body: req_body, params: params, method: method}) do
        Logger.debug("API Request: #{inspect(method)} #{inspect(url)} #{inspect(params)} #{inspect(req_body)}")
        Logger.debug("API Response: #{inspect(resp_body)} #{inspect(status_code)}")
        response
      end
      defp debug_response(resp, _req), do: resp

      def request(request) do
        super(request)
        |> debug_response(request)
        |> simplify_response(request)
      end

      def request!(method, url, body \\ "", headers \\ [], options \\ []) do
        case request(method, url, body, headers, options) do
          {:ok, body} -> body
          {:error, reason} -> raise Error, reason: reason
        end
      end
    end
  end

  def with_atom_keys(obj) do
    Map.new(obj, fn {k, v} ->
      v = if is_map(v), do: with_atom_keys(v), else: v
      {String.to_atom(k), v}
    end)
  end

  def as_atom(obj, key) do
    value = Map.get(obj, key)
    value = if value, do: String.to_atom(value), else: value
    Map.put(obj, key, value)
  end

  def as_timestamp(obj, key) do
    value = Map.get(obj, key)

    value = if value do
      {:ok, timestamp, 0} = DateTime.from_iso8601(value)
      timestamp
    else
      value
    end

    Map.put(obj, key, value)
  end
end
