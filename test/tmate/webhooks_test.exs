defmodule Tmate.WebhookTest do
  use ExUnit.Case, async: true
  alias Tmate.Session
  # require Tmate.ProtocolDefs, as: P
  require Logger

  defmodule Webhook.Mock do
    use GenServer

    def start_link(test_pid, opts \\ []) do
      GenServer.start_link(__MODULE__, test_pid, opts)
    end

    def init(test_pid) do
      state = %{test_pid: test_pid}
      Process.flag(:trap_exit, true)
      {:ok, state}
    end

    def emit_event(pid, event_type, entity_id, timestamp, params \\ %{}, _opts \\ []) do
      event = %{event_type: event_type, id: entity_id, timestamp: timestamp, params: params}
      # Not really necessary to go through the GenServer, but why not.
      GenServer.cast(pid, {:emit_event, event})
    end

    def handle_cast({:emit_event, event}, %{test_pid: test_pid}=state) do
      send(test_pid, {:webhook_event, event})
      {:noreply, state}
    end
  end

  defmodule Daemon do
    def send_msg(pid, msg) do
      send(pid, {:daemon_msg, msg})
    end
  end

  setup do
    webhooks = [{Webhook.Mock, self()}]
    {:ok, session} = Session.start_link([webhooks: webhooks, registry: {}], {Daemon, self()})
    {:ok, session: session}
  end

  # tests: TODO
  # assert_receive {:webhook_event, %{event_type: :session_disconnect, id: ^s3}}
  # assert_receive {:webhook_event, %{event_type: :session_disconnect, id: ^s4}}
  # refute_received {:webhook_event, _}
end
