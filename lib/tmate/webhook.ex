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

  @max_attempts 10
  @initial_retry_interval 300

  # We use a genserver per session because we don't want to block the session
  # process, but we still want to keep the events ordered.

  def start_link(webhook, opts \\ []) do
    GenServer.start_link(__MODULE__, webhook, opts)
  end

  def init(webhook) do
    state = %{url: webhook[:url], userdata: webhook[:userdata]}
    {:ok, state}
  end

  def emit_event(pid, event_type, entity_id, timestamp, params \\ %{}) do
    GenServer.cast(pid, {:emit_event, event_type, entity_id, timestamp, params})
  end

  def handle_cast({:emit_event, event_type, entity_id, timestamp, params}, state) do
    payload = Jason.encode!(%{type: event_type, entity_id: entity_id, timestamp: timestamp,
                              userdata: state.userdata, params: params})
    post_event(state.url, event_type, payload, 0)
    {:noreply, state}
  end

  defp post_event(url, event_type, payload, num_attempts) do
    case post_event_once(url, payload) do
      :ok -> :ok
      {:error, reason} ->
        if num_attempts == 0 do
          Logger.warn "Webhook fail on #{url} - Retrying event :#{event_type} (#{reason})"
        end

        case num_attempts do
          @max_attempts ->
            Logger.error "Webhook fail on #{url} - Dropping event :#{event_type} (#{reason})"
            :error
          _ ->
            :timer.sleep(@initial_retry_interval * Kernel.trunc(:math.pow(2, num_attempts)))
            post_event(url, event_type, payload, num_attempts + 1)
        end
    end
  end

  defp post_event_once(url, payload) do
    headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
    case HTTPoison.post(url, payload, headers, hackney: [pool: :default]) do
      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code >= 200 and status_code  < 300 ->
        :ok
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "status=#{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
