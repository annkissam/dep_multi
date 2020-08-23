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
    def handle_call({:list}, _from, list) do
      {:reply, list, list}
    end
  end

  setup do
    {:ok, counter} = start_supervised(Counter)

    [counter: counter]
  end

  test "processes dependencies", %{counter: counter} do
    # NOTE: the fn will only have dependencies in it? Something from the graph
    # only present dependency (and their parents) when calling the function

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

    assert results[:step_1] == "1"
    assert results[:step_2a] == "12A"
    assert results[:step_2b] == "12B"
    assert results[:step_3] == "3"
    assert results[:step_4] == "4"

    assert Counter.list(counter) == ["4", "1", "12B", "12A", "3"]

    # expect it to take >= 300ms & < 400ms
  end

  test "raise on cyclic graph", %{counter: counter} do
    assert_raise RuntimeError, "Cyclic Error", fn ->
      DepMulti.new()
      |> DepMulti.run(:step_1, [:step_2], Counter, :add, [counter, "1"])
      |> DepMulti.run(:step_2, [:step_1], Counter, :add, [counter, "2"])
      |> DepMulti.execute()
    end
  end

  # Question: If there's an error, do we force-quit the running processes, or wait?
  test "handles errors", %{counter: counter} do
    assert {:error, :step_2a, "Error thrown", changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [], fn _ ->
               :timer.sleep(100)
               Counter.add(counter, "1")
             end)
             |> DepMulti.run(:step_2a, [:step_1], fn _changes ->
               :timer.sleep(100)
               Counter.add(counter, "ERROR")
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

    assert changes == %{step_1: "1", step_2b: "12B", step_4: "4"}

    assert Counter.list(counter) == ["4", "1", "12B"]
  end

  test "handles exceptions", %{counter: counter} do
    assert {:terminate, :step_2a, {%RuntimeError{message: "Exception Thrown"}, _}, changes} =
             DepMulti.new()
             |> DepMulti.run(:step_1, [], fn _ ->
               :timer.sleep(100)
               Counter.add(counter, "1")
             end)
             |> DepMulti.run(:step_2a, [:step_1], fn _changes ->
               :timer.sleep(100)
               Counter.add(counter, "EXCEPTION")
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

    assert changes == %{step_1: "1", step_2b: "12B", step_4: "4"}

    assert Counter.list(counter) == ["4", "1", "12B"]
  end

  # Pending: Can we evaluate this before execution?
  # test "changes only includes direct (or indirect) dependencies", %{counter: counter}  do
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
