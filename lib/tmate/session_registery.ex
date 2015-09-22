defmodule Tmate.SessionRegistery do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, supervisor} = Tmate.SessionSupervisor.start_link
    {:ok, %{supervisor: supervisor, tokens_to_sessions: HashDict.new, sessions_to_tokens: HashDict.new}}
  end

  def new_session(registery, daemon) do
    GenServer.call(registery, {:new_session, daemon})
  end

  def register_session(registery, session, session_token) do
    GenServer.call(registery, {:register_session, session, session_token})
  end

  def get_session(registery, session_token) do
    GenServer.call(registery, {:get_session, session_token})
  end

  def handle_call({:new_session, daemon}, _from, state) do
    result = Tmate.SessionSupervisor.start_session(state.supervisor, [daemon])
    {:reply, result, state}
  end

  def handle_call({:register_session, session, session_token}, _from, state) do
    {:reply, :ok, add_session(state, session, session_token)}
  end

  def handle_call({:get_session, session_token}, _from, state) do
    {:reply, HashDict.fetch(state.tokens_to_sessions, session_token), state}
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    {:noreply, cleanup_session(state, pid)}
  end

  defp add_session(state, session, session_token) do
    case HashDict.fetch(state.tokens_to_sessions, session_token) do
      {:ok, _} -> raise "Session already exists: #{session_token}"
      :error -> # all good
    end

    ts = HashDict.put(state.tokens_to_sessions, session_token, session)
    st = HashDict.put(state.sessions_to_tokens, session, session_token)
    Process.monitor(session)
    %{state | tokens_to_sessions: ts, sessions_to_tokens: st}
  end

  defp cleanup_session(state, session) do
    session_token = HashDict.fetch!(state.sessions_to_tokens, session)
    ts = HashDict.delete(state.tokens_to_sessions, session_token)
    st = HashDict.delete(state.sessions_to_tokens, session)
    %{state | tokens_to_sessions: ts, sessions_to_tokens: st}
  end
end
