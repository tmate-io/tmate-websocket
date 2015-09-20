defmodule Tmate.SessionRegistery do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{sessions: HashDict.new}, opts)
  end

  def new_session(server, daemon) do
    GenServer.call(server, {:new_session, daemon})
  end

  def handle_call({:new_session, daemon}, _from, state) do
    {:ok, session} = Tmate.Session.start_link(self, daemon)
    {:reply, session, state}
  end
end
