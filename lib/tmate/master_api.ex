defmodule Tmate.MasterApi do
  def internal_api_opts do
    # XXX We can't pass the auth token directly, it is not
    # necessarily defined at compile time.
    Application.fetch_env!(:tmate, :master)[:internal_api]
  end
  use Tmate.Util.JsonApi, &__MODULE__.internal_api_opts/0

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
