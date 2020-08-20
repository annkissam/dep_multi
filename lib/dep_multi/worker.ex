defmodule DepMulti.Worker do
  use GenServer, restart: :temporary

  def start_link([state_server_pid, operations]) do
    GenServer.start_link(__MODULE__, [state_server_pid, operations])
  end

  def init(args) do
    send(self(), :run)

    {:ok, args}
  end

  def handle_info(:run, state) do
    DepMulti.Runner.run(self(), state.operations)

    {:noreply, state}
  end
end
