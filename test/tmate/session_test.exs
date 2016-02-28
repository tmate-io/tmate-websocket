defmodule Tmate.SessionTest do
  use ExUnit.Case, async: true
  alias Tmate.Session
  require Tmate.ProtocolDefs, as: P

  defmodule Master do
    def ping_master do
      :ping
    end

    def emit_event(_event_type, _entity_id, _params \\ %{}) do
      :ok
    end
  end

  defmodule Daemon do
    def daemon_pid(pid) do
      pid
    end

    def send_msg(pid, msg) do
      send(pid, {:daemon_msg, msg})
    end
  end

  def flush do
    receive do
      _ -> flush
    after
      0 ->
    end
  end

  setup do
    {:ok, session} = Session.start_link(Master, {Daemon, self})
    {:ok, session: session}
  end

  defp spawn_mock_websockets(session, n) do
    (1..n) |> Enum.map fn(i) ->
      pid = spawn fn -> :timer.sleep(:infinity) end
      Session.ws_request_sub(session, pid, %{ip_address: "ip#{i}"})
      pid
    end
  end

  test "client resizing", %{session: session} do
    ws = spawn_mock_websockets(session, 3)

    refute_received {:daemon_msg, [P.tmate_ctl_resize | _]}

    flush
    Session.notify_resize(session, ws |> Enum.at(0), {100, 200})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 200]}

    flush
    Session.notify_resize(session, ws |> Enum.at(1), {200, 100})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 100]}

    flush
    Session.notify_resize(session, ws |> Enum.at(2), {300, 300})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 100]}

    flush
    Session.notify_resize(session, ws |> Enum.at(1), {200, 50})
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 50]}

    flush
    :erlang.exit(ws |> Enum.at(1), :ok)
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 100, 200]}

    flush
    :erlang.exit(ws |> Enum.at(0), :ok)
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, 300, 300]}

    flush
    :erlang.exit(ws |> Enum.at(2), :ok)
    assert_receive {:daemon_msg, [P.tmate_ctl_resize, -1, -1]}
  end
end
