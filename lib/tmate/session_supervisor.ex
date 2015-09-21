defmodule Tmate.SessionSupervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def start_session(supervisor, args \\ []) do
    Supervisor.start_child(supervisor, args)
  end

  def init(:ok) do
    children = [
      worker(Tmate.Session, [], restart: :temporary)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end
