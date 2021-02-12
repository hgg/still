defmodule Still.Compiler.CompilationStage do
  @moduledoc """
  Almost every compilation request goes through `CompilationStage`. This
  process is responsible for keeping track of subscriptions (e.g: a browser
  subscribing to changes) and notifying all the subscribers of the end of the
  compilation cycle.

  Subscribers to this process are notified when the queue is empty, which is
  usefull to refresh the browser or finish the compilation task in production.

  Subscribers receive the event `:bus_empty` when `CompilationStage`'s compilation
  cycle is finished.

  There are many events that lead to a file being compiled:

  * when Still starts, all files are compiled;
  * files that change are compiled;
  * files that include files that have changed are compiled;
  * any many more.
  """
  use GenServer

  alias Still.Compiler.Incremental

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Asynchronously saves a file in the compilation list.

  Files are compiled in parallel, meaning that every 100ms the compilation stage
  will run and compile any due source file. When no more files are ready to be
  compiled, the subscribers are notified.
  """
  def compile(file) do
    GenServer.cast(__MODULE__, {:compile, file})
  end

  @doc """
  Save a subscription to the compilation cycle.
  """
  def subscribe do
    GenServer.call(__MODULE__, :subscribe)
  end

  @doc """
  Remove a subscription to the compilation cycle.
  """
  def unsubscribe do
    GenServer.call(__MODULE__, :unsubscribe)
  end

  @doc """
  Register a callback to be run after the compilation cycle but before the
  subscribers are notified. This function is meant to be used by development
  libraries only.

  It is particularly useful for making last minute additions after all the
  preprocessor pipelines have run, such as adding a generated sitemap or
  minifying assets.
  """
  def register(fun) do
    GenServer.cast(__MODULE__, {:register, fun})
  end

  @impl true
  def init(_) do
    state = %{
      to_compile: [],
      subscribers: [],
      callbacks: [],
      changed: false,
      timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:subscribe, {from, _}, state) do
    [from | state.subscribers] |> Enum.uniq()

    {:reply, :ok, %{state | subscribers: [from | state.subscribers] |> Enum.uniq()}}
  end

  def handle_call(:unsubscribe, {from, _}, state) do
    [from | state.subscribers] |> Enum.uniq()

    {:reply, :ok, %{state | subscribers: state.subscribers |> Enum.reject(&(&1 == from))}}
  end

  @impl true
  def handle_cast({:compile, files}, state) when is_list(files) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    {:noreply,
     %{
       state
       | to_compile: Enum.concat(files, state.to_compile),
         timer: Process.send_after(self(), :run, 100)
     }}
  end

  def handle_cast({:compile, file}, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    {:noreply,
     %{
       state
       | to_compile: [file | state.to_compile],
         timer: Process.send_after(self(), :run, 100)
     }}
  end

  def handle_cast({:register, fun}, state) do
    callbacks = [fun | state.callbacks] |> Enum.uniq()

    {:noreply, %{state | callbacks: callbacks}}
  end

  @impl true
  def handle_info(:run, %{to_compile: [], changed: true} = state) do
    state.callbacks
    |> Enum.each(fn fun -> fun.() end)

    state.subscribers
    |> Enum.each(fn pid ->
      send(pid, :bus_empty)
    end)

    {:noreply, %{state | changed: false, timer: nil}}
  end

  def handle_info(:run, %{to_compile: []} = state) do
    {:noreply, %{state | timer: nil}}
  end

  def handle_info(:run, state) do
    state.to_compile
    |> Enum.uniq()
    |> Enum.map(fn file ->
      Task.async(fn ->
        compile_file(file)
      end)
    end)
    |> Enum.map(fn task ->
      Task.await(task, Incremental.Node.compilation_timeout())
    end)

    Process.send_after(self(), :run, 900)

    {:noreply, %{state | to_compile: [], changed: true, timer: nil}}
  end

  defp compile_file("."), do: :ok

  defp compile_file("/"), do: :ok

  defp compile_file(file) do
    Incremental.Registry.get_or_create_file_process(file)
    |> Incremental.Node.compile()
    |> case do
      :ok ->
        :ok

      _ ->
        file |> Path.dirname() |> compile_file()
    end
  end
end
