defmodule DepMulti.RunnerSupervisor do
  use DynamicSupervisor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def execute(worker_pid, name, operation, changes) do
    spec = %{id: DepMulti.Runner, start: {DepMulti.Runner, :start_link, [[worker_pid, name, operation, changes]]}, restart: :temporary}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
