defmodule Tmate.Webhook do
  use GenServer
  require Logger

  # ~2.7 hours of retries
  @max_attempts 14
  @initial_retry_interval 300

  # We use a genserver per session because we don't want to block the session
  # process, but we still want to keep the events ordered.
  def start_link(webhook, opts \\ []) do
    GenServer.start_link(__MODULE__, webhook, opts)
  end

  def init(webhook) do
    state = %{url: webhook[:url], userdata: webhook[:userdata]}
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  def emit_event(pid, event_type, entity_id, timestamp, params \\ %{}, opts \\ []) do
    max_attempts = opts[:max_attempts] || @max_attempts
    GenServer.cast(pid, {:emit_event, event_type, entity_id, timestamp, params, max_attempts})
  end

  def handle_cast({:emit_event, event_type, entity_id, timestamp, params, max_attempts}, state) do
    do_emit_event(event_type, entity_id, timestamp, params, max_attempts, state)
    {:noreply, state}
  end

  defp do_emit_event(event_type, entity_id, timestamp, params, max_attempts, state) do
    payload = Jason.encode!(%{type: event_type, entity_id: entity_id, timestamp: timestamp,
                              userdata: state.userdata, params: params})
    post_event(state, event_type, payload, 1, max_attempts)
  end

  defp post_event(state, event_type, payload, num_attempts, max_attempts) do
    url = state.url
    case post_event_once(url, payload) do
      :ok -> :ok
      {:error, reason} ->
        if num_attempts == max_attempts do
          Logger.error "Webhook fail on #{url} - Dropping event :#{event_type} (#{reason})"
          :error
        else
          if num_attempts == 1 do
            Logger.warn "Webhook fail on #{url} - Retrying event :#{event_type} (#{reason})"
          end

          :timer.sleep(@initial_retry_interval * Kernel.trunc(:math.pow(2, num_attempts-1)))
          post_event(state, event_type, payload, num_attempts + 1, max_attempts)
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

  defmodule Many do
    def start_links(webhooks) do
      Enum.map(webhooks, fn {webhook_mod, webhook_opts} ->
        {:ok, pid} = webhook_mod.start_link(webhook_opts)
        pid
      end)
    end

    def emit_event(webhooks, pids, event_type, entity_id, timestamp, params \\ %{}, opts \\ []) do
      Enum.zip(webhooks, pids)
      |> Enum.each(fn {{webhook_mod, _webhook_opts}, pid} ->
        webhook_mod.emit_event(pid, event_type, entity_id, timestamp, params, opts)
      end)
    end
  end


  # defmodule Mock do
    # def start_link(webhook, opts \\ []) do
      # {:ok, self()}
    # end

    # def init(webhook) do
      # state = %{url: webhook[:url], userdata: webhook[:userdata]}
      # {:ok, state}
    # end

    # def emit_event(pid, event_type, entity_id, timestamp, params \\ %{}) do
      # GenServer.cast(pid, {:emit_event, event_type, entity_id, timestamp, params})
    # end
    # def emit_event_sync(opts, event_type, entity_id, timestamp, params \\ %{}) do
      # # %{type: event_type, entity_id: entity_id, timestamp: timestamp,
        # # userdata: state.userdata, params: params})
    # end
  # end
end
