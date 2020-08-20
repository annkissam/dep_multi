defmodule DepMulti.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      %{
        id: DepMulti.WorkerSupervisor,
        start: {DepMulti.WorkerSupervisor, :start_link, [[]]}
      }
    ]

    opts = [strategy: :one_for_one, name: DepMulti.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
