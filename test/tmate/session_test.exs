defmodule Tmate.SessionTest do
  use ExUnit.Case, async: true
  alias Tmate.Session
  require Tmate.ProtocolDefs, as: P

  defmodule Daemon do
    def send_msg(pid, msg) do
      send(pid, {:daemon_msg, msg})
    end
  end

  def flush do
    receive do
      _ -> flush()
    after
      0 -> nil
    end
  end

  setup do
    import Supervisor.Spec
    children = [worker(Tmate.SessionRegistry, [[name: Tmate.SessionRegistry]])]
    Supervisor.start_link(children, [strategy: :one_for_one, name: Tmate.Supervisor])

    {:ok, session} = Session.start_link(Tmate.Webhook.Null, {Daemon, self()})
    {:ok, session: session}
  end

  defp spawn_mock_websockets(session, n) do
    (1..n) |> Enum.map(fn(i) ->
      pid = spawn fn -> :timer.sleep(:infinity) end
      Session.ws_request_sub(session, pid, %{ip_address: "ip#{i}"})
      pid
    end)
  end

  test "client resizing", %{session: session} do
    Session.notify_daemon_msg(session, [P.tmate_ctl_header, 2,
                              "ip", "pubkey", "stoken", "stoken_ro", "ssh_cmd_fmt",
                              "client_version", 1])

    ws = spawn_mock_websockets(session, 3)

    refute_received {:daemon_msg, [P.tmate_ctl_resize | _]}

    flush()
    Session.notify_resize(session, ws |> Enum.at(0), {100, 200})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 200]}

    flush()
    Session.notify_resize(session, ws |> Enum.at(1), {200, 100})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 100]}

    flush()
    Session.notify_resize(session, ws |> Enum.at(2), {300, 300})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 100]}

    flush()
    Session.notify_resize(session, ws |> Enum.at(1), {200, 50})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 50]}

    flush()
    :erlang.exit(ws |> Enum.at(1), :ok)
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 200]}

    flush()
    :erlang.exit(ws |> Enum.at(0), :ok)
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 300, 300]}

    flush()
    :erlang.exit(ws |> Enum.at(2), :ok)
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, -1, -1]}
  end
end
