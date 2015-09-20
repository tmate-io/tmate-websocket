defmodule Tmate.TcpDaemon do
  @behaviour :ranch_protocol
  require Logger

  def start_link(ref, socket, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
    {:ok, pid}
  end

  def init(ref, socket, transport, _opts) do
    :ok = :ranch.accept_ack(ref)
    Logger.info("Daemon connection accepted")
    loop(%{socket: socket, transport: transport, mpac_buffer: <<>>})
  end

  def loop(state) do
    %{socket: socket, transport: transport, mpac_buffer: mpac_buffer} = state
    case transport.recv(socket, 0, :infinity) do
      {:ok, data} ->
        {:ok, state} = handle_data(state, mpac_buffer <> data)
        loop(state)
      {:error, err} ->
        Logger.info("Daemon connection terminated: #{err}")
        :ok = transport.close(socket)
    end
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

  defp handle_message(_state, msg) do
    Logger.info(inspect(msg))
    :ok
  end
end
