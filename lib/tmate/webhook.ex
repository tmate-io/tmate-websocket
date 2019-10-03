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

  # ~2.7 hours of retries
  @max_attempts 3
  @initial_retry_interval 3

  # We use a genserver per session because we don't want to block the session
  # process, but we still want to keep the events ordered.

  def start_link(webhook, opts \\ []) do
    GenServer.start_link(__MODULE__, webhook, opts)
  end

  def init(webhook) do
    state = %{url: webhook[:url], userdata: webhook[:userdata], max_attempts: @max_attempts}
    {:ok, state}
  end

  def emit_event(pid, event_type, entity_id, timestamp, params \\ %{}) do
    GenServer.cast(pid, {:emit_event, event_type, entity_id, timestamp, params})
  end

  def emit_event_sync(opts, event_type, entity_id, timestamp, params \\ %{}) do
    state = %{url: opts[:url], userdata: opts[:userdata], max_attempts: 1}
    do_emit_event({event_type, entity_id, timestamp, params}, state)
  end

  def handle_cast({:emit_event, event_type, entity_id, timestamp, params}, state) do
    do_emit_event({event_type, entity_id, timestamp, params}, state)
    {:noreply, state}
  end

  defp do_emit_event({event_type, entity_id, timestamp, params}, state) do
    payload = Jason.encode!(%{type: event_type, entity_id: entity_id, timestamp: timestamp,
                              userdata: state.userdata, params: params})
    post_event(state, event_type, payload, 1)
  end

  defp post_event(state, event_type, payload, num_attempts) do
    url = state.url
    case post_event_once(url, payload) do
      :ok -> :ok
      {:error, reason} ->
        if num_attempts == state.max_attempts do
          Logger.error "Webhook fail on #{url} - Dropping event :#{event_type} (#{reason})"
          :error
        else
          if num_attempts == 1 do
            Logger.warn "Webhook fail on #{url} - Retrying event :#{event_type} (#{reason})"
          end

          :timer.sleep(@initial_retry_interval * Kernel.trunc(:math.pow(2, num_attempts-1)))
          post_event(state, event_type, payload, num_attempts + 1)
        end
    end
  end

  defp post_event_once(url, payload) do
    headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
    # We need force_redirect: true, otherwise, post data doesn't get reposted.
    case HTTPoison.post(url, payload, headers, hackney: [pool: :default, force_redirect: true], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code >= 200 and status_code  < 300 ->
        :ok
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "status=#{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
