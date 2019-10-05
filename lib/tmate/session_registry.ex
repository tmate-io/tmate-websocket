defmodule Tmate.SessionRegistry do
  use GenServer
  require Logger

  require Record
  Record.defrecord :session, [:stoken, :stoken_ro, :id, :pid, :monitor]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, %{sessions: []}}
  end

  def register_session(registry, pid, id, stoken, stoken_ro) do
    GenServer.call(registry, {:register_session, pid, id, stoken, stoken_ro}, :infinity)
  end

  def get_session(registry, token) do
    GenServer.call(registry, {:get_session, token}, :infinity)
  end

  def get_session_by_id(registry, id) do
    GenServer.call(registry, {:get_session_by_id, id}, :infinity)
  end

  defmacrop lookup_session(state, what, token) do
    quote do: List.keyfind(unquote(state).sessions, unquote(token), session(unquote(what)))
  end

  def handle_call({:register_session, pid, id, stoken, stoken_ro}, _from, state) do
    {:reply, :ok, add_session(state, pid, id, stoken, stoken_ro)}
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

  def handle_call({:get_session_by_id, id}, _from, state) do
    cond do
      session = lookup_session(state, :id, id) ->
        {:reply, session(session, :pid), state}
      true -> {:reply, :error, state}
    end
  end

  defp add_session(state, pid, id, stoken, stoken_ro) do
    if s = lookup_session(state, :id,        id   ) ||
           lookup_session(state, :stoken,    stoken   ) ||
           lookup_session(state, :stoken,    stoken_ro) ||
           lookup_session(state, :stoken_ro, stoken_ro) ||
           lookup_session(state, :stoken_ro, stoken   ) do
      Logger.info("Replacing stale session #{id}")
      state = kill_session(state, s, {:shutdown, :stale})
      add_session(state, pid, id, stoken, stoken_ro)
    else
      monitor = Process.monitor(pid)
      new_session = session(stoken: stoken, stoken_ro: stoken_ro,
                            id: id, pid: pid, monitor: monitor)
      %{state | sessions: [new_session | state.sessions]}
    end
  end

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    {:noreply, cleanup_session(state, pid)}
  end

  defp cleanup_session(state, pid) do
    %{state | sessions: List.keydelete(state.sessions, pid, session(:pid))}
  end

  defp kill_session(state, session, reason) do
    Process.demonitor(session(session, :monitor), [:flush])
    Process.exit(session(session, :pid), reason)
    cleanup_session(state, session(session, :pid))
  end
end
