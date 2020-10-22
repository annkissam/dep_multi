defmodule DepMultiTest do
  use ExUnit.Case
  doctest DepMulti

  defmodule Counter do
    use GenServer

    def start_link(args \\ []) do
      GenServer.start_link(__MODULE__, args)
    end

    def add(_server, "EXCEPTION") do
      raise "Exception Thrown"
    end

    def add(_server, "ERROR") do
      {:error, "Error thrown"}
    end

    def add(server, str) do
      GenServer.call(server, {:add, str})
    end

    def fetch(map, server, key, value) do
      GenServer.call(server, {:fetch, map, key, value})
    end

    def list(server) do
      GenServer.call(server, {:list})
    end

    @impl true
    def init(_args) do
      {:ok, []}
    end

    @impl true
    def handle_call({:add, str}, _from, list) do
      {:reply, {:ok, str}, list ++ [str]}
    end

    @impl true
    def handle_call({:fetch, map, key, new_value}, _from, list) do
      value = Map.fetch!(map, key)
      str = "#{value}-#{new_value}"
      {:reply, {:ok, str}, list ++ [str]}
    end

    @impl true
    def handle_call({:list}, _from, list) do
      {:reply, list, list}
    end
  end

  setup do
    {:ok, counter} = start_supervised(Counter)

    [counter: counter]
  end

  test "processes dependencies", %{counter: counter} do
    {:ok, results} =
      DepMulti.new()
      |> DepMulti.run(:step_1, [], fn _ ->
        :timer.sleep(100)
        Counter.add(counter, "1")
      end)
      |> DepMulti.run(:step_2a, [dependencies: [:step_1]], fn %{step_1: str} ->
        :timer.sleep(100)
        Counter.add(counter, "#{str}-2A")
      end)
      |> DepMulti.run(:step_2b, [dependencies: [:step_1]], Counter, :fetch, [
        counter,
        :step_1,
        "2B"
      ])
      |> DepMulti.run(:step_3, [dependencies: [:step_2a, :step_2b]], fn %{
                                                                          step_1: _,
                                                                          step_2a: _,
                                                                          step_2b: _
                                                                        } ->
        :timer.sleep(100)
        Counter.add(counter, "3")
      end)
      |> DepMulti.run(:step_4, [], fn _ ->
        :timer.sleep(50)
        Counter.add(counter, "4")
      end)
      |> DepMulti.execute()

    assert results[:step_1] == "1"
    assert results[:step_2a] == "1-2A"
    assert results[:step_2b] == "1-2B"
    assert results[:step_3] == "3"
    assert results[:step_4] == "4"

    assert Counter.list(counter) == ["4", "1", "1-2B", "1-2A", "3"]

    # expect it to take >= 300ms & < 350ms
  end

  test "terminates on cyclic graph", %{counter: counter} do
    assert {:terminate, nil, {%RuntimeError{message: "Cyclic Error"}, _}, changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [dependencies: [:step_2]], Counter, :fetch, [
               counter,
               :step_2,
               "1"
             ])
             |> DepMulti.run(:step_2, [dependencies: [:step_1]], Counter, :fetch, [
               counter,
               :step_1,
               "2"
             ])
             |> DepMulti.execute()

    assert changes == %{}

    assert Counter.list(counter) == []
  end

  test "handles errors", %{counter: counter} do
    assert {:error, :step_2a, "Error thrown", changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [], fn _ ->
               :timer.sleep(100)
               Counter.add(counter, "1")
             end)
             |> DepMulti.run(:step_2a, [dependencies: [:step_1]], fn _changes ->
               # :timer.sleep(100)
               Counter.add(counter, "ERROR")
             end)
             |> DepMulti.run(:step_2b, [dependencies: [:step_1]], Counter, :fetch, [
               counter,
               :step_1,
               "2B"
             ])
             |> DepMulti.run(:step_3, [dependencies: [:step_2a, :step_2b]], fn %{
                                                                                 step_1: _,
                                                                                 step_2a: _,
                                                                                 step_2b: _
                                                                               } ->
               :timer.sleep(100)
               Counter.add(counter, "3")
             end)
             |> DepMulti.run(:step_4, [], fn _ ->
               :timer.sleep(50)
               Counter.add(counter, "4")
             end)
             |> DepMulti.execute()

    assert changes == %{step_1: "1", step_2b: "1-2B", step_4: "4"}

    assert Counter.list(counter) == ["4", "1", "1-2B"]
  end

  test "handles exceptions", %{counter: counter} do
    assert {:terminate, :step_2a, {%RuntimeError{message: "Exception Thrown"}, _}, changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [], fn _ ->
               :timer.sleep(100)
               Counter.add(counter, "1")
             end)
             |> DepMulti.run(:step_2a, [dependencies: [:step_1]], fn _changes ->
               # :timer.sleep(100)
               Counter.add(counter, "EXCEPTION")
             end)
             |> DepMulti.run(:step_2b, [dependencies: [:step_1]], Counter, :fetch, [
               counter,
               :step_1,
               "2B"
             ])
             |> DepMulti.run(:step_3, [dependencies: [:step_2a, :step_2b]], fn %{
                                                                                 step_1: _,
                                                                                 step_2a: _,
                                                                                 step_2b: _
                                                                               } ->
               :timer.sleep(100)
               Counter.add(counter, "3")
             end)
             |> DepMulti.run(:step_4, [], fn _ ->
               :timer.sleep(50)
               Counter.add(counter, "4")
             end)
             |> DepMulti.execute()

    assert changes == %{step_1: "1", step_2b: "1-2B", step_4: "4"}

    assert Counter.list(counter) == ["4", "1", "1-2B"]
  end

  test "only receives direct dependencies in changes", %{counter: counter} do
    assert {:terminate, :step_3, {:function_clause, _}, changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [], fn _ ->
               :timer.sleep(100)
               Counter.add(counter, "1")
             end)
             |> DepMulti.run(:step_2a, [dependencies: [:step_1]], fn %{step_1: str} ->
               :timer.sleep(100)
               Counter.add(counter, "#{str}-2A")
             end)
             |> DepMulti.run(:step_2b, [dependencies: [:step_1]], Counter, :fetch, [
               counter,
               :step_1,
               "2B"
             ])
             |> DepMulti.run(:step_3, [dependencies: [:step_2a, :step_2b]], fn %{
                                                                                 step_1: _,
                                                                                 step_2a: _,
                                                                                 step_2b: _,
                                                                                 step_4: _
                                                                               } ->
               :timer.sleep(100)
               Counter.add(counter, "3")
             end)
             |> DepMulti.run(:step_4, [], fn _ ->
               :timer.sleep(50)
               Counter.add(counter, "4")
             end)
             |> DepMulti.execute()

    assert changes == %{step_1: "1", step_2b: "1-2B", step_2a: "1-2A", step_4: "4"}

    assert Counter.list(counter) == ["4", "1", "1-2B", "1-2A"]
  end

  test "handles timeouts", %{counter: counter} do
    assert {:terminate, :step_2a, :timeout, changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [], fn _ ->
               :timer.sleep(100)
               Counter.add(counter, "1")
             end)
             |> DepMulti.run(:step_2a, [dependencies: [:step_1], timeout: 50], fn %{step_1: str} ->
               :timer.sleep(100)
               Counter.add(counter, "#{str}-2A")
             end)
             |> DepMulti.run(:step_2b, [dependencies: [:step_1]], Counter, :fetch, [
               counter,
               :step_1,
               "2B"
             ])
             |> DepMulti.run(:step_3, [dependencies: [:step_2a, :step_2b]], fn %{
                                                                                 step_1: _,
                                                                                 step_2a: _,
                                                                                 step_2b: _
                                                                               } ->
               :timer.sleep(100)
               Counter.add(counter, "3")
             end)
             |> DepMulti.run(:step_4, [], fn _ ->
               :timer.sleep(50)
               Counter.add(counter, "4")
             end)
             |> DepMulti.execute()

    assert changes == %{step_1: "1", step_2b: "1-2B", step_4: "4"}

    assert Counter.list(counter) == ["4", "1", "1-2B"]
  end
end
