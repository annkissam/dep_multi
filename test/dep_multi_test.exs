defmodule DepMultiTest do
  use ExUnit.Case
  doctest DepMulti

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
    {:ok, counter} = start_supervised(Counter)

    # NOTE: the fn will only have dependencies in it? Something from the graph
    # only present depednendency (and their parents) when calling the function

    {:ok, results} =
      DepMulti.new()
      |> DepMulti.run(:step_1, [], fn _ ->
        :timer.sleep(100)
        Counter.add(counter, "1")
      end)
      |> DepMulti.run(:step_2a, [:step_1], fn %{step_1: str} ->
        :timer.sleep(100)
        Counter.add(counter, "#{str}2A")
      end)
      |> DepMulti.run(:step_2b, [:step_1], fn %{step_1: str} ->
        :timer.sleep(50)
        Counter.add(counter, "#{str}2B")
      end)
      |> DepMulti.run(:step_3, [:step_2a, :step_2b], fn _ ->
        :timer.sleep(100)
        Counter.add(counter, "3")
      end)
      |> DepMulti.run(:step_4, [], Counter, :add, [counter, "4"])
      |> DepMulti.execute()

    # assert DepMulti.to_list(dep_multi)

    assert results[:step_1] == "1"
    assert results[:step_2a] == "12A"
    assert results[:step_2b] == "12B"
    assert results[:step_3] == "3"
    assert results[:step_4] == "4"

    assert Counter.list(counter) == ["4", "1", "12B", "12A", "3"]

    # expect it to take >= 300ms & < 400ms
  end

  test "raise on cyclic graph" do
    counter = start_supervised(Counter)

    assert_raise RuntimeError, "Cyclic Error", fn ->
      DepMulti.new()
      |> DepMulti.run(:step_1, [:step_2], Counter, :add, [counter, "1"])
      |> DepMulti.run(:step_2, [:step_1], Counter, :add, [counter, "2"])
      |> DepMulti.execute()
    end
  end

  # Pending: Can we evaluate this before execution?
  # test "changes only include dependencies" do
  #   assert_raise RuntimeError, "~Pattern Match Error", fn ->
  #     DepMulti.new()
  #       |> DepMulti.run(:step_1, [], Counter, :add, [counter, "1"])
  #       |> DepMulti.run(:step_2, [], fn (%{step_1: str}) ->
  #         Counter.add(counter, "2")
  #       end)
  #       |> DepMulti.execute()
  #   end
  # end
end
