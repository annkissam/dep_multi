defmodule DepServerTest do
  use ExUnit.Case
  doctest DepServer

  defmodule Counter do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def add(server, str) do
      GenServer.call(server, {:add, str})
    end

    def list(server) do
      GenServer.call(server, {:list})
    end

    @impl true
    def init(:ok) do
      {:ok, []}
    end

    @impl true
    def handle_call({:add, str}, _from, list) do
      {:reply, {:ok, str}, list ++ [str]}
    end

    def handle_call({:list}, _from, list) do
      {:reply, list, list}
    end
  end

  # Question: If there's an error, do we force-quit the running processes, or wait?
  test "processes dependencies" do
    counter = start_supervised(Counter)

    # NOTE: the fn will only have dependencies in it? Something from the graph
    # only present depednendency (and their parents) when calling the function

    {:ok, results} = DepServer.new()
      |> DepServer.add(:step_1, [], fn (_) ->
        :timer.sleep(100)
        Counter.add(counter, "1")
      end)
      |> DepServer.add(:step_2a, [:step_1], fn (%{step_1: str}) ->
        :timer.sleep(100)
        Counter.add(counter, "#{str}2A")
      end)
      |> DepServer.add(:step_2b, [:step_1], fn (%{step_1: str}) ->
        :timer.sleep(50)
        Counter.add(counter, "#{str}2B")
      end)
      |> DepServer.add(:step_3, [:step_2a, :step_2b], fn (_) ->
        :timer.sleep(100)
        Counter.add(counter, "3")
      end)
      |> DepServer.add(:step_4, [], fn (_) ->
        :timer.sleep(50)
        Counter.add(counter, "4")
      end)
      |> DepServer.exec()

    expect(results[:step_1]).to eq("1")
    expect(results[:step_2a]).to eq("12A")
    expect(results[:step_2b]).to eq("12B")
    expect(results[:step_3]).to eq("3")
    expect(results[:step_4]).to eq("4")

    expect(Counter.list(counter)).to eq(["4", "1", "12B", "12A", "3"])

    # expect it to take >= 300ms & < 400ms
  end
end
