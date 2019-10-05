defmodule Tmate.WebApiTest do
  use ExUnit.Case
  use Plug.Test

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

  defp expect_error(func) do
    try do
      func.()
      raise "No error raised"
    catch
      _, _ -> nil
    end
  end

  defp register_new_session(registry, id, stoken, stoken_ro) do
    {registry_mod, registry_pid} = registry
    pid = spawn(fn -> receive do end end)
    registry_mod.register_session(registry_pid, pid, id, stoken, stoken_ro)
  end


  setup do
    webhooks = [{Webhook.Mock, self()}]
    registry = {Tmate.SessionRegistry, Tmate.SessionRegistry.WebApiTest}
    Tmate.SessionRegistry.start_link([name: Tmate.SessionRegistry.WebApiTest])

    session_opts = [webhooks: webhooks, registry: registry]
    router = fn conn -> Tmate.WebApi.call(conn, session_opts) end
    {:ok, router: router, registry: registry}
  end

  def flush do
    receive do
      m ->
        IO.inspect(m)
        flush()
    after
      0 -> nil
    end
  end

  describe "/master_api/report_active_sessions" do
    test "authentication required", %{router: router} do
      conn = conn(:post, "/master_api/report_active_sessions", %{})
      expect_error(fn -> router.(conn) end)
      {status, _, _} = sent_resp(conn)
      assert status == 401

      conn = conn(:post, "/master_api/report_active_sessions", %{wsapi_key: "xxx"})
      expect_error(fn -> router.(conn) end)
      {status, _, _} = sent_resp(conn)
      assert status == 401
    end

    test "prune sessions", %{router: router, registry: registry} do
      s1 = UUID.uuid1()
      s2 = UUID.uuid1()
      s3 = UUID.uuid1()
      s4 = UUID.uuid1()

      register_new_session(registry, s1, "s1", "s1ro")
      register_new_session(registry, s2, "s2", "s2ro")

      payload = %{auth_key: "webhookkey", sessions: [s3, s4]}
      conn = conn(:post, "/master_api/report_active_sessions", payload)
      |> router.()

      assert conn.status == 200

      assert_receive {:webhook_event, %{event_type: :session_disconnect, id: ^s3}}
      assert_receive {:webhook_event, %{event_type: :session_disconnect, id: ^s4}}
      refute_received {:webhook_event, _}
    end
  end
end
