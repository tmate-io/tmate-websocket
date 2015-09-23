defmodule Tmate.WebSocketEvent do
  use GenServer

  def start_link(ws, opts \\ []) do
    GenServer.start_link(__MODULE__, ws, opts)
  end

  def init(ws) do
    {:ok, %{ws: ws}}
  end

  def subscribe(wse, event_manager) do
    GenServer.call(wse, {:subscribe, event_manager})
  end

  def send_msg(wse, msg) do
    GenServer.call(wse, {:send_msg, msg})
  end

  def handle_call({:subscribe, event_manager}, _from, state) do
    GenEvent.add_mon_handler(event_manager, Tmate.WebSocketEvent.Handler, state.ws)
    {:reply, :ok, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    send state.ws, {:send_msg, msg}
    {:reply, :ok, state}
  end
end

defmodule Tmate.WebSocketEvent.Handler do
  use GenEvent

  def init(ws) do
    {:ok, %{ws: ws}}
  end

  def handle_event(msg, state) do
    send state.ws, {:send_msg, msg}
    {:ok, state}
  end
end
