defmodule DepMulti.State do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_args) do
    {:ok,
      %{
        processing: [],
        success: [],
        failure: [],
        done: false
      }
    }
  end
end
