defmodule Tmate.Session do
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

  def feed_daemon_message(session, msg) do
    GenServer.cast(session, {:feed_daemon_message, msg})
  end

  def handle_info({:DOWN, _ref, _type, _pid, _info}, state) do
    {:stop, :normal, state}
  end

  def terminate(_reason, _state) do
    Logger.info "Terminated session"
    :ok
  end

  def handle_cast({:feed_daemon_message, msg}, state) do
    {:ok, state} = handle_msg(state, msg)
    {:noreply, state}
  end

  defp handle_msg(state, [0, protocol_version, ip_address, pubkey,
                             session_token, session_token_to]) do
    Logger.info("Session token: #{session_token}")
    {:ok, %{state | session_token: session_token}}
  end

  defp handle_msg(state, _) do
    {:ok, state}
  end

  defp send_msg(state, msg) do
    Tmate.DaemonTcp.send_msg(state.daemon, msg)
  end
end
