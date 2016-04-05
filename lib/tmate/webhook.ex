defmodule Tmate.Webhook do
  defmodule Null do
    use GenServer
    def start_link(_, opts \\ []) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end
    def init(:ok) do
      {:ok, {}}
    end
    def emit_event(_, _, _, _, _ \\ %{}), do: :ok
  end

  use GenServer
  require Logger

  @max_retry 5
  @retry_interval 3000

  # We use a genserver per session because we don't want to block the session
  # process, but we still want to keep the events ordered.

  def start_link(urls, opts \\ []) do
    GenServer.start_link(__MODULE__, urls, opts)
  end

  def init(urls) do
    state = %{urls: urls}
    {:ok, state}
  end

  def emit_event(pid, event_type, entity_id, userdata, params \\ %{}) do
    GenServer.cast(pid, {:emit_event, event_type, entity_id, userdata, params})
  end

  def handle_cast({:emit_event, event_type, entity_id, userdata, params}, state) do
    # TODO also include timestamp
    payload = Poison.encode!(%{type: event_type, entity_id: entity_id, userdata: userdata, params: params})
    state.urls |> Enum.each(& post_event(&1, event_type, payload, @max_retry))
    {:noreply, state}
  end

  defp post_event(url, event_type, payload, retry_count) do
    case post_event_once(url, payload) do
      :ok -> :ok
      {:error, reason} ->
        case retry_count do
          0 ->
            Logger.warn "Webhook fail on #{url} - Dropping event :#{event_type} (#{reason})"
            :error
          _ ->
            :timer.sleep(@retry_interval)
            post_event(url, event_type, payload, retry_count - 1)
        end
    end
  end

  defp post_event_once(url, payload) do
    headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
    case HTTPoison.post(url, payload, headers) do
      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code >= 200 and status_code  < 300 ->
        :ok
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "status=#{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
