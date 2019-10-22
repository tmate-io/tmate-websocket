defmodule Tmate.MasterApi do
  {:ok, master_options} = Application.fetch_env(:tmate, :master)
  use Tmate.Util.JsonApi, master_options[:internal_api]
  require Logger

  defp map_convert_string_keys_to_atom(map) do
    Map.new(map, fn {k, v} ->
      v = if is_map(v), do: map_convert_string_keys_to_atom(v), else: v
      {String.to_atom(k), v}
    end)
  end

  defp format_timestamp(obj, key) do
    value = Map.get(obj, key)

    value = if value do
      {:ok, timestamp, 0} = DateTime.from_iso8601(value)
      timestamp
    else
      value
    end

    Map.put(obj, key, value)
  end

  def get_session(token) do
    case get("/session", [], params: %{token: token}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: session}} ->
        session = session
        |> map_convert_string_keys_to_atom()
        |> format_timestamp(:disconnected_at)
        |> format_timestamp(:created_at)
        {:ok, session}
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :not_found
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Internal API error. reason=#{reason}")
        :error
    end
  end
end
