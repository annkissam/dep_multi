defmodule DepMulti.Worker do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # blocked = [{name, dependencies, {:run, run}}]
  # processing = [{pid, name, dependencies, {:run, run}}]
  # success = %{name, result}

  def init([server_pid, ref, operations, shutdown]) do
    send(self(), :run)

    # :digraph.delete/1
    # Deletes digraph G. This call is important as digraphs are implemented with
    # ETS. There is no garbage collection of ETS tables. However, the digraph is
    # deleted if the process that created the digraph terminates
    #
    # For that reason, we create the digraph in this (temporary) GenServer that
    # will terminate on completion / exception
    graph = build_graph(operations)

    state = %{
      blocked: operations,
      processing: [],
      success: %{},
      error: nil,
      server_pid: server_pid,
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
      Enum.split_with(state.blocked, fn %DepMulti.Operation{dependencies: dependencies} ->
        Enum.all?(dependencies, fn dependency ->
          Enum.any?(state.success, fn {name, _result} -> name == dependency end)
        end)
      end)

    new_processing =
      Enum.map(unblocked, fn %DepMulti.Operation{name: name, run_cmd: run_cmd, timeout: timeout} =
                               operation ->
        all_dependencies = :digraph_utils.reachable_neighbours([name], state.graph)

        # To prevent stochastic issues, only pass changes that are in the dependency graph
        filtered_success = Map.take(state.success, all_dependencies)

        {:ok, runner_pid} =
          DepMulti.RunnerSupervisor.execute(self(), name, run_cmd, filtered_success)

        if timeout == :infinity do
          %DepMulti.ProcessingOperation{runner_pid: runner_pid, operation: operation}
        else
          timeout_ref = make_ref()
          timer_pid = Process.send_after(self(), {:timeout, timeout_ref}, timeout)

          %DepMulti.ProcessingOperation{
            runner_pid: runner_pid,
            operation: operation,
            timer_pid: timer_pid,
            timeout_ref: timeout_ref
          }
        end
      end)

    state =
      state
      |> Map.put(:blocked, blocked)
      |> Map.put(:processing, new_processing ++ state.processing)

    {:noreply, state}
  end

  def handle_info({:timeout, timeout_ref}, state) do
    {timed_out, processing} =
      Enum.split_with(state.processing, fn %DepMulti.ProcessingOperation{timeout_ref: ref} ->
        timeout_ref == ref
      end)

    state =
      state
      |> Map.put(:processing, processing)

    if Enum.empty?(timed_out) do
      # already processed, no need to timeout
      {:noreply, state}
    else
      %DepMulti.ProcessingOperation{operation: %DepMulti.Operation{name: name}} =
        List.first(timed_out)

      {:stop, {:timeout, name}, state}
    end
  end

  def handle_cast({:runner_success, runner_pid, operation_name, result}, state) do
    {completed, processing} =
      Enum.split_with(state.processing, fn %DepMulti.ProcessingOperation{runner_pid: pid} ->
        runner_pid == pid
      end)

    if Enum.empty?(completed) do
      raise "Unknown Runner: #{inspect(operation_name)}"
    end

    %DepMulti.ProcessingOperation{timer_pid: timer_pid} = List.first(completed)

    if timer_pid do
      :erlang.cancel_timer(timer_pid)
    end

    success = Map.put(state.success, operation_name, result)

    state =
      state
      |> Map.put(:success, success)
      |> Map.put(:processing, processing)

    if Enum.empty?(state.processing) && Enum.empty?(state.blocked) do
      case state.error do
        {type, failed_operation_name, failed_operation_result} ->
          GenServer.cast(
            state.server_pid,
            {:response, state.ref,
             {type, failed_operation_name, failed_operation_result, state.success}}
          )

        nil ->
          GenServer.cast(state.server_pid, {:response, state.ref, {:ok, state.success}})
      end

      {:stop, :normal, state}
    else
      unless state.error do
        send(self(), :run)
      end

      {:noreply, state}
    end
  end

  def handle_cast({:runner_failure, runner_pid, operation_name, error}, state) do
    {failed, processing} =
      Enum.split_with(state.processing, fn %DepMulti.ProcessingOperation{runner_pid: pid} ->
        runner_pid == pid
      end)

    if Enum.empty?(failed) do
      raise "Unknown Runner: #{inspect(operation_name)}"
    end

    %DepMulti.ProcessingOperation{timer_pid: timer_pid} = List.first(failed)

    if timer_pid do
      :erlang.cancel_timer(timer_pid)
    end

    # Should this overwrite state.error?

    state =
      state
      |> Map.put(:error, {:error, operation_name, error})
      |> Map.put(:processing, processing)

    if Enum.empty?(state.processing) do
      GenServer.cast(
        state.server_pid,
        {:response, state.ref, {:error, operation_name, error, state.success}}
      )

      {:stop, :normal, state}
    else
      if state.shutdown do
        Enum.each(state.processing, fn {pid, _operation} ->
          GenServer.stop(pid, :shutdown)
        end)
      end

      {:noreply, state}
    end
  end

  def handle_cast({:runner_terminate, runner_pid, operation_name, reason}, state) do
    {terminated, processing} =
      Enum.split_with(state.processing, fn %DepMulti.ProcessingOperation{runner_pid: pid} ->
        runner_pid == pid
      end)

    if Enum.empty?(terminated) do
      raise "Unknown Runner: #{inspect(operation_name)}"
    end

    %DepMulti.ProcessingOperation{timer_pid: timer_pid} = List.first(terminated)

    if timer_pid do
      :erlang.cancel_timer(timer_pid)
    end

    # Should this overwrite state.error?

    state =
      state
      |> Map.put(:error, {:terminate, operation_name, reason})
      |> Map.put(:processing, processing)

    if Enum.empty?(state.processing) do
      GenServer.cast(
        state.server_pid,
        {:response, state.ref, {:terminate, operation_name, reason, state.success}}
      )

      {:stop, :normal, state}
    else
      # If a runner encounters an exception, kill everything
      # if state.shutdown do
      Enum.each(state.processing, fn {pid, _operation} ->
        GenServer.stop(pid, :shutdown)
      end)

      # end

      {:noreply, state}
    end
  end

  def terminate(:normal, _state) do
    :ok
  end

  def terminate(reason, %{
        server_pid: server_pid,
        ref: ref,
        processing: processing,
        success: success
      }) do
    Enum.each(processing, fn %DepMulti.ProcessingOperation{runner_pid: runner_pid} ->
      GenServer.stop(runner_pid, :shutdown)
    end)

    case reason do
      {:timeout, name} ->
        GenServer.cast(server_pid, {:response, ref, {:terminate, name, :timeout, success}})

      _ ->
        GenServer.cast(server_pid, {:response, ref, {:terminate, nil, reason, success}})
    end

    :ok
  end

  defp build_graph(operations) do
    graph = :digraph.new()

    Enum.each(operations, fn %DepMulti.Operation{name: name, dependencies: dependencies} ->
      :digraph.add_vertex(graph, name)

      Enum.each(dependencies, fn dependency ->
        :digraph.add_vertex(graph, dependency)
        :digraph.add_edge(graph, name, dependency)
      end)
    end)

    graph
  end
end
