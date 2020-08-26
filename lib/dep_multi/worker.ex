defmodule DepMulti.Worker do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # blocked = [{name, dependencies, {:run, run}}]
  # processing = [{pid, name, dependencies, {:run, run}}]
  # success = %{name, result}

  def init([pid, ref, operations, shutdown]) do
    send(self(), :run)

    graph = build_graph(operations)

    state = %{
      blocked: operations,
      processing: [],
      success: %{},
      error: nil,
      pid: pid,
      ref: ref,
      graph: graph,
      shutdown: shutdown
    }

    unless :digraph_utils.is_acyclic(graph) do
      raise "Cyclic Error"
    end

    {:ok, state}
  end

  def runner_success(worker_pid, runner_pid, name, result) do
    GenServer.cast(worker_pid, {:runner_success, runner_pid, name, result})
  end

  def runner_failure(worker_pid, runner_pid, name, error) do
    GenServer.cast(worker_pid, {:runner_failure, runner_pid, name, error})
  end

  def runner_terminate(worker_pid, runner_pid, name, reason) do
    GenServer.cast(worker_pid, {:runner_terminate, runner_pid, name, reason})
  end

  def handle_info(:run, state) do
    {unblocked, blocked} =
      Enum.split_with(state.blocked, fn {_name, dependencies, _operation} ->
        Enum.all?(dependencies, fn dependency ->
          Enum.any?(state.success, fn {name, _result} -> name == dependency end)
        end)
      end)

    new_processing =
      Enum.map(unblocked, fn {name, dependencies, operation} ->
        all_dependencies = :digraph_utils.reachable_neighbours([name], state.graph)

        # To prevent stochastic issues, only pass changes that are in the dependency graph
        filtered_success = Map.take(state.success, all_dependencies)

        {:ok, pid} = DepMulti.RunnerSupervisor.execute(self(), name, operation, filtered_success)
        {pid, name, dependencies, operation}
      end)

    state =
      state
      |> Map.put(:blocked, blocked)
      |> Map.put(:processing, new_processing ++ state.processing)

    {:noreply, state}
  end

  def handle_cast({:runner_success, runner_pid, runner_name, result}, state) do
    {completed, processing} =
      Enum.split_with(state.processing, fn {pid, name, _dependencies, _operation} ->
        runner_pid == pid && runner_name == name
      end)

    if Enum.empty?(completed) do
      raise "Unknown Runner: #{inspect(runner_name)}"
    end

    success = Map.put(state.success, runner_name, result)

    state =
      state
      |> Map.put(:success, success)
      |> Map.put(:processing, processing)

    if Enum.empty?(state.processing) && Enum.empty?(state.blocked) do
      case state.error do
        {type, failed_operation, failed_value} ->
          GenServer.cast(
            state.pid,
            {:response, state.ref, {type, failed_operation, failed_value, state.success}}
          )

        nil ->
          GenServer.cast(state.pid, {:response, state.ref, {:ok, state.success}})
      end

      {:stop, :normal, state}
    else
      unless state.error do
        send(self(), :run)
      end

      {:noreply, state}
    end
  end

  def handle_cast({:runner_failure, runner_pid, runner_name, error}, state) do
    {failed, processing} =
      Enum.split_with(state.processing, fn {pid, name, _dependencies, _operation} ->
        runner_pid == pid && runner_name == name
      end)

    if Enum.empty?(failed) do
      raise "Unknown Runner: #{inspect(runner_name)}"
    end

    # Should this overwrite state.error?

    state =
      state
      |> Map.put(:error, {:error, runner_name, error})
      |> Map.put(:processing, processing)

    if Enum.empty?(state.processing) do
      GenServer.cast(
        state.pid,
        {:response, state.ref, {:error, runner_name, error, state.success}}
      )

      {:stop, :normal, state}
    else
      if state.shutdown do
        Enum.each(state.processing, fn {pid, _name, _dependencies, _operation} ->
          GenServer.stop(pid, :shutdown)
        end)
      end

      {:noreply, state}
    end
  end

  def handle_cast({:runner_terminate, runner_pid, runner_name, reason}, state) do
    {terminated, processing} =
      Enum.split_with(state.processing, fn {pid, name, _dependencies, _operation} ->
        runner_pid == pid && runner_name == name
      end)

    if Enum.empty?(terminated) do
      raise "Unknown Runner: #{inspect(runner_name)}"
    end

    # Should this overwrite state.error?

    state =
      state
      |> Map.put(:error, {:terminate, runner_name, reason})
      |> Map.put(:processing, processing)

    if Enum.empty?(state.processing) do
      GenServer.cast(
        state.pid,
        {:response, state.ref, {:terminate, runner_name, reason, state.success}}
      )

      {:stop, :normal, state}
    else
      if state.shutdown do
        Enum.each(state.processing, fn {pid, _name, _dependencies, _operation} ->
          GenServer.stop(pid, :shutdown)
        end)
      end

      {:noreply, state}
    end
  end

  def terminate(:normal, _state) do
    :ok
  end

  def terminate(reason, %{pid: pid, ref: ref, processing: processing, success: success}) do
    Enum.each(processing, fn {pid, _name, _dependencies, _operation} ->
      GenServer.stop(pid, :shutdown)
    end)

    GenServer.cast(pid, {:response, ref, {:terminate, nil, reason, success}})

    :ok
  end

  defp build_graph(operations) do
    graph = :digraph.new()

    Enum.each(operations, fn {name, dependencies, _operation} ->
      :digraph.add_vertex(graph, name)

      Enum.each(dependencies, fn dependency ->
        :digraph.add_vertex(graph, dependency)
        :digraph.add_edge(graph, name, dependency)
      end)
    end)

    graph
  end
end
