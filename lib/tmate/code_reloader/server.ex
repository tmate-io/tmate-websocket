# Copied from the Phoenix codebase

# The GenServer used by the CodeReloader.
defmodule Tmate.CodeReloader.Server do
  @moduledoc false
  use GenServer

  require Logger
  alias Tmate.CodeReloader.Proxy

  def start_link(path, compilers, opts \\ []) do
    GenServer.start_link(__MODULE__, {path, compilers}, opts)
  end

  def reload! do
    case :erlang.whereis(Tmate.CodeReloader.Server) do
      :undefined -> :ok
      pid -> GenServer.call(pid, :reload!, :infinity)
    end
  end

  ## Callbacks

  def init({path, compilers}) do
    all = Mix.Project.config[:compilers] || Mix.compilers
    compilers = all -- (all -- compilers)
    {:ok, {path, compilers}}
  end

  def handle_call(:reload!, from, {paths, compilers} = state) do
    froms = all_waiting([from])
    reply = mix_compile(Code.ensure_loaded(Mix.Task), paths, compilers)
    Enum.each(froms, &GenServer.reply(&1, reply))
    {:noreply, state}
  end

  defp all_waiting(acc) do
    receive do
      {:"$gen_call", from, :reload!} -> all_waiting([from | acc])
    after
      0 -> acc
    end
  end

  defp mix_compile({:error, _reason}, _, _) do
    Logger.error "If you want to use the code reload plug in production or " <>
                 "inside an escript, add :mix to your list of dependencies or " <>
                 "disable code reloading"
    :ok
  end

  defp mix_compile({:module, Mix.Task}, paths, compilers) do
    mix_compile(paths, compilers)
  end

  defp mix_compile(paths, compilers) do
    reloadable_paths = Enum.flat_map(paths, &["--elixirc-paths", &1])
    Enum.each compilers, &Mix.Task.reenable("compile.#{&1}")

    {res, out} =
      proxy_io(fn ->
        try do
          Enum.each compilers, &Mix.Task.run("compile.#{&1}", reloadable_paths)
        catch
          _, _ -> :error
        end
      end)

    cond do
      :error in res -> {:error, out}
      :ok in res    -> :ok
      true          -> :noop
    end
  end

  defp proxy_io(fun) do
    original_gl = Process.group_leader
    {:ok, proxy_gl} = Proxy.start()
    Process.group_leader(self(), proxy_gl)

    try do
      res = fun.()
      {List.wrap(res), Proxy.stop(proxy_gl)}
    after
      Process.group_leader(self(), original_gl)
      Process.exit(proxy_gl, :kill)
    end
  end
end
