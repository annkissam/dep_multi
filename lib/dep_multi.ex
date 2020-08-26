defmodule DepMulti do
  @moduledoc """
  `DepMulti` is a data structure for performing dependant asynchronous
  operations.

  To demonstrate the problem, image you have three asynchronous tasks:

  ##
    [
      Task.async(fn -> do_some_work() end),
      Task.async(fn -> do_some_other_work() end),
      Task.async(fn -> do_more_work() end),
    ] |> Enum.map(&Task.await/1)

  This works until you have a dependency / ordering issue. Say `do_more_work`
  must happen after `do_some_work`. At that point, you'll need to name each
  task and reference those names in other tasks that are dependant on them. If
  those dependant task needs data from a previous task, you'll also want pass
  those changes into the function.

  The API to solve this issue is based on `Ecto.Multi`(https://hexdocs.pm/ecto/Ecto.Multi.html),
  and specifically `run/3` and `run/5`. The differences are:
  * The tasks are executed asychronously
  * the `run` methods take a list of dependencies and a timeout
  * the changes passed into the function only include direct or indirect
  dependencies

  ## Example
    iex>   DepMulti.new()
    ...>   |> DepMulti.run(:step_1, [], fn _ ->
    ...>     {:ok, 1}
    ...>   end)
    ...>   |> DepMulti.run(:step_2a, [dependencies: [:step_1], timeout: 5000], fn %{step_1: value} ->
    ...>     {:ok, 2 + value}
    ...>   end)
    ...>   |> DepMulti.run(:step_2b, [dependencies: [:step_1]], Map, :fetch, [:step_1])
    ...>   |> DepMulti.execute()
    {:ok, %{step_1: 1, step_2a: 3, step_2b: 1}}
  """

  alias __MODULE__
  defstruct operations: [], names: MapSet.new()

  @type changes :: map
  @type run :: (changes -> {:ok | :error, any}) | {module, atom, [any]}
  @type dependencies :: list(name)
  @type run_cmd :: {:run, run}
  @type operations :: [DepMulti.Operation.t()]
  @type names :: MapSet.t()
  @type name :: any
  @type t :: %__MODULE__{operations: operations, names: names}

  @doc """
  Returns an empty `DepMulti` struct.

  ## Example

      iex> DepMulti.new() |> DepMulti.to_list()
      []
  """
  @spec new :: t
  def new do
    %DepMulti{}
  end

  @doc """
  Adds a function to run as part of the multi.

  The function should return either `{:ok, value}` or `{:error, value}`,
  and receives the changes so far as the only argument.

  NOTE: The changes will only include direct or indirect dependencies

  ## Example

      DepMulti.run(multi, :write, [:image], fn %{image: image} ->
        with :ok <- File.write(image.name, image.contents) do
          {:ok, nil}
        end
      end)
  """
  @spec run(t, name, keyword, run) :: t
  def run(multi, name, opts, run) when is_function(run, 1) do
    add_operation(multi, name, opts, {:run, run})
  end

  @doc """
  Adds a function to run as part of the multi.

  Similar to `run/4`, but allows to pass module name, function and arguments.
  The function should return either `{:ok, value}` or `{:error, value}`, and
  receives the rthe changes so far as the first argument (prepended to those
  passed in the call to the function).

  NOTE: The changes will only include direct or indirect dependencies
  """
  @spec run(t, name, keyword, module, function, args) :: t when function: atom, args: [any]
  def run(multi, name, opts, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    add_operation(multi, name, opts, {:run, {mod, fun, args}})
  end

  @spec add_operation(t, name, keyword, {:run, run}) :: t
  defp add_operation(%DepMulti{} = multi, name, opts, run_cmd) do
    %{operations: operations, names: names} = multi

    if MapSet.member?(names, name) do
      raise "#{inspect(name)} is already a member of the DepMulti: \n#{inspect(multi)}"
    end

    timeout = Keyword.get(opts, :timeout, :infinity)
    dependencies = Keyword.get(opts, :dependencies, [])

    unknown_keys = Keyword.keys(opts) -- [:timeout, :dependencies]

    unless Enum.empty?(unknown_keys) do
      raise "Unknown keys: #{inspect(unknown_keys)}"
    end

    operation = %DepMulti.Operation{
      name: name,
      dependencies: dependencies,
      run_cmd: run_cmd,
      timeout: timeout
    }

    %{
      multi
      | operations: [operation | operations],
        names: MapSet.put(names, name)
    }
  end

  @doc """
  Returns the list of operations stored in `multi`.
  """
  @spec to_list(t) :: operations
  def to_list(%DepMulti{operations: operations}) do
    operations
    |> Enum.reverse()
  end

  @spec execute(t, keyword) ::
          {:ok, changes} | {:error, name, any, changes} | {:terminate, name, any, changes}
  def execute(multi, opts \\ []) do
    operations = Enum.reverse(multi.operations)

    DepMulti.Server.execute(operations, opts)
  end
end
