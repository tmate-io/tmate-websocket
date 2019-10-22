defmodule Tmate.Util.JsonApi do
  defmacro __using__(opts) do
    quote do
      use HTTPoison.Base
      alias HTTPoison.Response
      alias HTTPoison.Error
      require Logger

      @api_opts unquote(opts)

      defp api_opts() do
        if is_function(@api_opts), do: @api_opts.(), else: @api_opts
      end

      def process_url(url) do
        api_opts()[:base_url] <> url
      end

      def process_request_headers(headers) do
        auth_token = api_opts()[:auth_token]
        auth_headers = if auth_token, do: [{"Authorization", "Bearer " <> auth_token}], else: []
        json_headers =  [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
        headers ++ auth_headers ++ json_headers
      end

      def process_request_body(""), do: ""
      def process_request_body(body) do
        Jason.encode!(body)
      end

      defp report_errors(%Response{request_url: request_url, status_code: status_code}=response) do
        if status_code >= 300 and status_code != 404 do
          Logger.warn("API error #{request_url} [#{status_code}]")
        end
      end

      def process_response(%Response{headers: headers, body: body} = response) do
        content_type_hdr = Enum.find(headers, fn {name, _} -> name == "content-type" end)
        body = case content_type_hdr do
          {_, "application/json" <> _} -> Jason.decode!(body)
          _ -> body
        end

        report_errors(response)

        %{response | body: body}
      end
    end
  end
end
