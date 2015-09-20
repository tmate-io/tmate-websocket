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
    session = Tmate.SessionRegistery.new_session(Tmate.SessionRegistery, self)

    Logger.info("Daemon connection accepted")

    state = %{socket: socket, transport: transport, session: session, mpac_buffer: <<>>}
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def send_msg(server, msg) do
    GenServer.cast(server, {:send_msg, msg})
  end

  def handle_call(_resquest, _from, state) do
    {:reply, :ok, state}
  end

  def handle_info({:tcp, socket, data},
                  state=%{socket: socket, transport: transport, mpac_buffer: mpac_buffer}) do
    :ok = transport.setopts(socket, [active: :once])
    {:ok, state} = handle_data(state, mpac_buffer <> data)
    {:noreply, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.info("Daemon connection errored: #{reason}")
    {:stop, reason, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Daemon connection closed")
    {:stop, :normal, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  def handle_cast({:send_msg, msg}, state) do
    {:ok, data} = MessagePack.pack(msg)
    :ok = state.transport.send(state.socket, data)
    {:noreply, state}
  end

  defp handle_data(state, data) do
    case MessagePack.unpack_once(data) do
      {:ok, {msg, rest}} ->
        :ok = handle_message(state, msg)
        handle_data(state, rest)
      {:error, :incomplete} ->
        {:ok, %{state | mpac_buffer: data}}
    end
  end

  defp handle_message(state, msg) do
    Tmate.Session.feed_daemon_message(state.session, msg)
  end
end
