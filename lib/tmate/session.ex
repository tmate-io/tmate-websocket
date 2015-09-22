defmodule Tmate.Session do
  require Tmate.ProtocolDefs, as: P
  use GenServer
  require Logger

  def start_link(daemon, opts \\ []) do
    GenServer.start_link(__MODULE__, daemon, opts)
  end

  def init(daemon) do
    Process.monitor(daemon)
    {:ok, %{daemon: daemon}}
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

    :ok = Tmate.SessionRegistery.register_session(Tmate.SessionRegistery, self, session_token)
    Map.merge(state, %{session_token: session_token})
  end

  defp receive_ctl_msg(state, [P.tmate_ctl_deamon_out_msg, dmsg]) do
    state = send_deamon_msg_to_websockets(state, dmsg)
    receive_daemon_msg(state, dmsg)
  end

  defp receive_ctl_msg(state, [cmd | _]) do
    Logger.warn("Unknown message type=#{cmd}")
    state
  end

  defp send_deamon_msg_to_websockets(state, _dmsg) do
    state
  end

  defp receive_daemon_msg(state, [P.tmate_out_header, protocol_version,
                                  _client_version_string]) do
    Map.merge(state, %{daemon_protocol_version: protocol_version})
  end

  defp receive_daemon_msg(state, _msg) do
    # TODO
    state
  end

  defp send_msg(state, msg) do
    Tmate.DaemonTcp.send_msg(state.daemon, msg)
  end
end
