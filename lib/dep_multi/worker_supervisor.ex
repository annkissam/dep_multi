defmodule DepMulti.WorkerSupervisor do
  use DynamicSupervisor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def execute(pid, ref, operations) do
    spec = %{
      id: DepMulti.Worker,
      start: {DepMulti.Worker, :start_link, [[pid, ref, operations]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
