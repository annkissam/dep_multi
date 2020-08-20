defmodule DepMulti.WorkerSupervisor do
  use DynamicSupervisor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_work(operations) do
    {:ok, state_pid} = supervise_state_server()
    supervise_worker_server(state_pid, operations)
    {:ok, state_pid}
  end

  defp supervise_state_server do
    spec = %{id: DepMulti.State, start: {DepMulti.State, :start_link, [[]]}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  defp supervise_worker_server(state_pid, operations) do
    spec = %{id: DepMulti.Worker, start: {DepMulti.Worker, :start_link, [[state_pid, operations]]}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
