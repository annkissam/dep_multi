defmodule DepMulti.Server do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{}}
  end

  def execute(operations, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:run, operations}, timeout)
  end

  def handle_call({:run, operations}, from, state) do
    ref = make_ref()

    state = Map.put(state, ref, from)

    DepMulti.WorkerSupervisor.execute(self(), ref, operations)

    {:noreply, state}
  end

  def handle_cast({:response, ref, response}, state) do
    {from, state} = Map.pop(state, ref)

    # if from do
    GenServer.reply(from, response)
    # end

    {:noreply, state}
  end
end
