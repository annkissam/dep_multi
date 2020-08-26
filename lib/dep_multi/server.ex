defmodule DepMulti.Server do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{}}
  end

  @spec execute([DepMulti.Operation.t()], keyword) ::
          {:ok, DepMulti.changes()}
          | {:error, DepMulti.name(), any, DepMulti.changes()}
          | {:terminate, DepMulti.name(), any, DepMulti.changes()}
  def execute(operations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    shutdown = Keyword.get(opts, :shutdown, false)

    GenServer.call(__MODULE__, {:run, operations, shutdown}, timeout)
  end

  def handle_call({:run, operations, shutdown}, from, state) do
    ref = make_ref()

    # state = Map.put(state, ref, from)
    #
    # {:ok, _pid} = DepMulti.WorkerSupervisor.execute(self(), ref, operations, shutdown)
    #
    # {:noreply, state}

    case DepMulti.WorkerSupervisor.execute(self(), ref, operations, shutdown) do
      {:ok, _pid} ->
        state = Map.put(state, ref, from)

        {:noreply, state}

      {:error, reason} ->
        {:reply, {:terminate, nil, reason, %{}}, state}
    end
  end

  def handle_cast({:response, ref, response}, state) do
    {from, state} = Map.pop(state, ref)

    GenServer.reply(from, response)

    {:noreply, state}
  end
end
