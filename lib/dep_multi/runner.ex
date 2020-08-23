defmodule DepMulti.Runner do
  use GenServer

  def start_link([worker_pid, name, operation, changes]) do
    GenServer.start_link(__MODULE__, [worker_pid, name, operation, changes])
  end

  def init([worker_pid, name, operation, changes]) do
    send(self(), :run)

    {:ok,
     %{
       worker_pid: worker_pid,
       name: name,
       operation: operation,
       changes: changes
     }}
  end

  def success(runner_pid, result) do
    GenServer.cast(runner_pid, {:success, result})
  end

  def failure(runner_pid, error) do
    GenServer.cast(runner_pid, {:failure, error})
  end

  def handle_info(:run, %{operation: operation, changes: changes} = state) do
    result = run(operation, changes)

    case result do
      {:ok, result} ->
        success(self(), result)

      {:error, error} ->
        failure(self(), error)
    end

    {:noreply, state}
  end

  defp run({:run, run}, changes) when is_function(run, 1) do
    run.(changes)
  end

  defp run({:run, {mod, fun, args}}, _changes)
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    apply(mod, fun, args)
  end

  def handle_cast({:success, result}, %{worker_pid: worker_pid, name: name} = state) do
    DepMulti.Worker.runner_success(worker_pid, self(), name, result)

    {:stop, :normal, state}
  end

  def handle_cast({:failure, error}, %{worker_pid: worker_pid, name: name} = state) do
    DepMulti.Worker.runner_failure(worker_pid, self(), name, error)

    {:stop, :normal, state}
  end

  def terminate(:normal, _state) do
    :ok
  end

  def terminate(:shutdown, _state) do
    :ok
  end

  def terminate(reason, %{worker_pid: worker_pid, name: name}) do
    DepMulti.Worker.runner_terminate(worker_pid, self(), name, reason)

    :ok
  end
end
