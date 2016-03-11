defmodule Tmate.SessionRegistry do
  use GenServer
  require Logger

  require Record
  Record.defrecord :session, [:stoken, :stoken_ro, :pid]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, supervisor} = Tmate.SessionSupervisor.start_link
    {:ok, %{supervisor: supervisor, sessions: []}}
  end

  def new_session(registry, daemon_args) do
    GenServer.call(registry, {:new_session, daemon_args}, :infinity)
  end

  def register_session(registry, pid, stoken, stoken_ro) do
    GenServer.call(registry, {:register_session, pid, stoken, stoken_ro}, :infinity)
  end

  def get_session(registry, token) do
    GenServer.call(registry, {:get_session, token}, :infinity)
  end

  defmacrop lookup_session(state, what, token) do
    quote do: :lists.keyfind(unquote(token), session(unquote(what))+1, unquote(state).sessions)
  end

  def handle_call({:new_session, daemon_args}, _from, state) do
    {:ok, master_options} = Application.fetch_env(:tmate, :master)
    master_endpoint = if master_options[:nodes], do: Tmate.MasterEndpoint,
                                               else: Tmate.MasterEndpoint.Null
    result = Tmate.SessionSupervisor.start_session(state.supervisor,
               [master_endpoint, daemon_args])
    {:reply, result, state}
  end

  def handle_call({:register_session, pid, stoken, stoken_ro}, _from, state) do
    {:reply, :ok, add_session(state, pid, stoken, stoken_ro)}
  end

  def handle_call({:get_session, token}, _from, state) do
    cond do
      session = lookup_session(state, :stoken, token) ->
        {:reply, {:rw, session(session, :pid)}, state}
      session = lookup_session(state, :stoken_ro, token) ->
        {:reply, {:ro, session(session, :pid)}, state}
      true -> {:reply, :error, state}
    end
  end

  defp add_session(state, pid, stoken, stoken_ro) do
    if lookup_session(state, :stoken,    stoken   ) ||
       lookup_session(state, :stoken,    stoken_ro) ||
       lookup_session(state, :stoken_ro, stoken_ro) ||
       lookup_session(state, :stoken_ro, stoken   ) do
         # This should never happen, but we are never too careful.
         raise "Session token already registered: #{stoken}"
    end

    Process.monitor(pid)
    new_session = session(stoken: stoken, stoken_ro: stoken_ro, pid: pid)
    %{state | sessions: [new_session | state.sessions]}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    {:noreply, cleanup_session(state, pid)}
  end

  defp cleanup_session(state, pid) do
    %{state | sessions: :lists.keydelete(pid, session(:pid)+1, state.sessions)}
  end
end
