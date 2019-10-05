defmodule Tmate.WebhookEventsTest do
  use ExUnit.Case, async: true
  alias Tmate.Session
  require Tmate.ProtocolDefs, as: P
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

    def emit_event(pid, event, _opts \\ []) do
      GenServer.cast(pid, {:emit_event, event})
    end

    def handle_cast({:emit_event, event}, %{test_pid: test_pid}=state) do
      event = Jason.decode!(Jason.encode!(event))
      send(test_pid, {:webhook_event, event})
      {:noreply, state}
    end
  end

  defmodule Daemon do
    def send_msg(pid, msg) do
      send(pid, {:daemon_msg, msg})
    end
  end

  def start_link_session() do
    webhooks = [{Webhook.Mock, self()}]
    session_opts = [webhooks: webhooks, registry: {}]
    {:ok, session} = Session.start_link(session_opts, {Daemon, self()})
    session
  end

  test "events" do
    session = start_link_session()
    Session.notify_daemon_msg(session, [P.tmate_ctl_header, 2,
                              "ip", "pubkey", "stoken", "stoken_ro", "ssh_cmd_fmt",
                              "client_version", 6])

    Session.notify_daemon_msg(session, [P.tmate_ctl_deamon_out_msg, [P.tmate_out_ready]])
    assert_receive {:webhook_event,
      %{"type" => "session_register",
        "entity_id" => session_id,
        "generation" => 1,
        "params" => %{
          "stoken" => "stoken",
          "stoken_ro" => "stoken_ro",
          "ssh_cmd_fmt" => "ssh_cmd_fmt",
          "reconnected" => false,
          "pubkey" => "pubkey",
          "ip_address" => "ip",
          "client_version" => "client_version"
        }
      }}
    assert_receive {:daemon_msg, [P.tmate_ctl_deamon_fwd_msg,
                     [P.tmate_in_set_env, "tmate_reconnection_data", reconnection_data]]}

    Session.notify_daemon_msg(session, [P.tmate_ctl_client_join, 33, "c1ip", "c1pubkey", false])
    assert_receive {:webhook_event,
      %{"type" => "session_join",
        "entity_id" => ^session_id,
        "generation" => 1,
        "params" => %{
          "id" => c1_id,
          "readonly" => false,
          "type" => "ssh",
          "identity" => "c1pubkey",
          "ip_address" => "c1ip"
        }
      }}

    Process.unlink(session)
    Process.exit(session, {:shutdown, :tcp_close})
    assert_receive {:webhook_event,
      %{"type" => "session_disconnect",
        "entity_id" => ^session_id,
        "generation" => 1,
        "params" => %{}
      }}

    session = start_link_session()
    Session.notify_daemon_msg(session, [P.tmate_ctl_header, 2,
                              "ip", "pubkey", "stoken", "stoken_ro", "ssh_cmd_fmt",
                              "client_version", 6])
    Session.notify_daemon_msg(session, [P.tmate_ctl_deamon_out_msg,
                                         [P.tmate_out_reconnect, reconnection_data]])
    Session.notify_daemon_msg(session, [P.tmate_ctl_deamon_out_msg, [P.tmate_out_ready]])
    assert_receive {:webhook_event,
      %{"type" => "session_register",
        "entity_id" => ^session_id,
        "generation" => 2,
        "params" => %{
          "stoken" => "stoken",
          "stoken_ro" => "stoken_ro",
          "ssh_cmd_fmt" => "ssh_cmd_fmt",
          "reconnected" => true,
          "pubkey" => "pubkey",
          "ip_address" => "ip",
          "client_version" => "client_version"
        }
      }}

    Session.notify_daemon_msg(session, [P.tmate_ctl_client_join, 34, "c2ip", "c2pubkey", true])
    assert_receive {:webhook_event,
      %{"type" => "session_join",
        "entity_id" => ^session_id,
        "generation" => 2,
        "params" => %{
          "id" => c2_id,
          "readonly" => true,
          "type" => "ssh",
          "identity" => "c2pubkey",
          "ip_address" => "c2ip"
        }
      }}

    Session.notify_daemon_msg(session, [P.tmate_ctl_client_left, 34])
    assert_receive {:webhook_event,
      %{"type" => "session_left",
        "entity_id" => ^session_id,
        "generation" => 2,
        "params" => %{
          "id" => ^c2_id
        }
      }}

    Process.unlink(session)
    Session.notify_daemon_msg(session, [P.tmate_ctl_deamon_out_msg, [P.tmate_out_fin]])
    assert_receive {:webhook_event,
      %{"type" => "session_close",
        "entity_id" => ^session_id,
        "generation" => 2,
        "params" => %{}
      }}
  end
end
