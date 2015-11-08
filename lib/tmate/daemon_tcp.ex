defmodule Tmate.DaemonTcp do
  @behaviour :ranch_protocol
  require Logger
  use GenServer

  def start_link(ref, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, opts])
  end

  def init(ref, socket, transport, _opts) do
    :ok = :proc_lib.init_ack({:ok, self})

    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, [active: :once])
    {:ok, session} = Tmate.SessionRegistry.new_session(Tmate.SessionRegistry,
                      {__MODULE__, {self, socket, transport}})

    Process.link(session)
    Logger.debug("Accepted daemon connection")

    state = %{socket: socket, transport: transport, session: session, mpac_buffer: <<>>}
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def daemon_pid({pid, _, _}) do
    pid
  end

  def handle_info({:tcp, socket, data},
                  state=%{socket: socket, transport: transport, mpac_buffer: mpac_buffer}) do
    :ok = transport.setopts(socket, [active: :once])
    {:ok, state} = receive_data(state, mpac_buffer <> data)
    {:noreply, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warn("Daemon connection errored: #{reason}")
    {:stop, reason, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("Closed daemon connection")
    {:stop, :normal, state}
  end

  defp receive_data(state, data) do
    case MessagePack.unpack_once(data) do
      {:ok, {msg, rest}} ->
        :ok = Tmate.Session.notify_daemon_msg(state.session, msg)
        receive_data(state, rest)
      {:error, :incomplete} ->
        {:ok, %{state | mpac_buffer: data}}
    end
  end

  def send_msg({_pid, socket, transport}, msg) do
    # no need to go through the daemon process.
    # the caller process is linked to the daemon process anyways,
    # and the serialization doesn't need to be offloaded.
    transport.send(socket, MessagePack.pack!(msg, enable_string: true))
  end
end
