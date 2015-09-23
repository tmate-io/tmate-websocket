defmodule Tmate.SessionRegistery do
  use GenServer
  require Logger

  require Record
  Record.defrecord :session, [:session_token, :session_token_ro, :pid]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, supervisor} = Tmate.SessionSupervisor.start_link
    {:ok, %{supervisor: supervisor, sessions: []}}
  end

  def new_session(registery, daemon) do
    GenServer.call(registery, {:new_session, daemon})
  end

  def register_session(registery, pid, session_token, session_token_ro) do
    GenServer.call(registery, {:register_session, pid, session_token, session_token_ro})
  end

  def get_session(registery, token) do
    GenServer.call(registery, {:get_session, token})
  end

  defmacrop lookup_session(state, what, token) do
    quote do: :lists.keyfind(unquote(token), session(unquote(what))+1, unquote(state).sessions)
  end

  def handle_call({:new_session, daemon}, _from, state) do
    result = Tmate.SessionSupervisor.start_session(state.supervisor, [daemon])
    {:reply, result, state}
  end

  def handle_call({:register_session, pid, session_token, session_token_ro}, _from, state) do
    {:reply, :ok, add_session(state, pid, session_token, session_token_ro)}
  end

  def handle_call({:get_session, token}, _from, state) do
    # Remove "ro-" prefix, it's just sugar.
    token = case token do
      "ro-" <> rest -> rest
      rest -> rest
    end

    cond do
      session = lookup_session(state, :session_token, token) ->
        {:reply, {:rw, session(session, :pid)}, state}
      session = lookup_session(state, :session_token_ro, token) ->
        {:reply, {:ro, session(session, :pid)}, state}
      true -> {:reply, :error, state}
    end
  end

  defp add_session(state, pid, session_token, session_token_ro) do
    if lookup_session(state, :session_token,    session_token   ) ||
       lookup_session(state, :session_token,    session_token_ro) ||
       lookup_session(state, :session_token_ro, session_token_ro) ||
       lookup_session(state, :session_token_ro, session_token   ) do
         # This should never happen, but we are never too careful.
         raise "Session token already registered: #{session_token}"
    end

    Process.monitor(pid)
    new_session = session(session_token: session_token, session_token_ro: session_token_ro, pid: pid)
    %{state | sessions: [new_session | state.sessions]}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    {:noreply, cleanup_session(state, pid)}
  end

  defp cleanup_session(state, pid) do
    %{state | sessions: :lists.keydelete(pid, session(:pid)+1, state.sessions)}
  end
end
