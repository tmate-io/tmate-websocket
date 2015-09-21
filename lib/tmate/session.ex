defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P
  use GenServer
  require Logger

  def start_link(registery, daemon, opts \\ []) do
    state = %{registery: registery, daemon: daemon, session_token: nil}
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    Process.monitor(state.daemon)
    {:ok, state}
  end

  def handle_info({:DOWN, _ref, _type, _pid, _info}, state) do
    Logger.info("Session finished")
    {:stop, :normal, state}
  end

  def feed_daemon_message(session, msg) do
    GenServer.call(session, {:feed_daemon_message, msg})
  end

  def handle_call({:feed_daemon_message, msg}, _from, state) do
    {:reply, :ok, receive_ctl_msg(state, msg)}
  end

  defp receive_ctl_msg(state, [P.tmate_ctl_auth, _protocol_version, _ip_address, _pubkey,
                               session_token, _session_token_to]) do
    Logger.metadata([session_token: session_token])
    Logger.info("Session started")
    Tmate.SessionRegistery.register_session(state.registery, self, session_token)
    %{state | session_token: session_token}
  end

  defp receive_ctl_msg(state, [P.tmate_ctl_deamon_out_msg, _time, msg]) do
    receive_daemon_msg(state, msg)
  end

  defp receive_ctl_msg(state, [P.tmate_ctl_keyframe | _msg]) do
    # todo keyframe
    state
  end

  defp receive_ctl_msg(state, _) do
    Logger.warn("Unknown message")
    state
  end

  defp receive_daemon_msg(state, _msg) do
    state
  end

  defp send_msg(state, msg) do
    Tmate.DaemonTcp.send_msg(state.daemon, msg)
  end
end
