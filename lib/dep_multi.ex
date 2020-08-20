defmodule DepMulti do
  @moduledoc """
  Documentation for DepMulti.
  """

  alias __MODULE__
  defstruct operations: [], names: MapSet.new()

  @type changes :: map
  @type run :: ((changes) -> {:ok | :error, any}) | {module, atom, [any]}
  @type dependencies :: list(name)
  @typep operation :: {:run, run}
  @typep operations :: [{name, dependencies, operation}]
  @typep names :: MapSet.t
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

  ## Example

      DepMulti.run(multi, :write, [], fn %{image: image} ->
        with :ok <- File.write(image.name, image.contents) do
          {:ok, nil}
        end
      end)
  """
  @spec run(t, name, dependencies, run) :: t
  def run(multi, name, dependencies, run) when is_function(run, 1) do
    add_operation(multi, name, dependencies, {:run, run})
  end

  @doc """
  Adds a function to run as part of the multi.

  Similar to `run/4`, but allows to pass module name, function and arguments.
  The function should return either `{:ok, value}` or `{:error, value}`, and
  receives the repo as the first argument, and the changes so far as the
  second argument (prepended to those passed in the call to the function).
  """
  @spec run(t, name, dependencies, module, function, args) :: t when function: atom, args: [any]
  def run(multi, name, dependencies, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    add_operation(multi, name, dependencies, {:run, {mod, fun, args}})
  end

  @spec add_operation(t, name, dependencies, {:run, run}) :: t
  defp add_operation(%DepMulti{} = multi, name, dependencies, operation) do
    %{operations: operations, names: names} = multi

    if MapSet.member?(names, name) do
      raise "#{inspect name} is already a member of the DepMulti: \n#{inspect multi}"
    else
      %{multi | operations: [{name, dependencies, operation} | operations],
                names: MapSet.put(names, name)}
    end
  end

  @doc """
  Returns the list of operations stored in `multi`.
  """
  @spec to_list(t) :: [{name, term}]
  def to_list(%DepMulti{operations: operations}) do
    operations
    |> Enum.reverse
  end

  @spec execute(t) :: {:ok, term} | {:error, term}
  def execute(multi) do
    operations = Enum.reverse(multi.operations)

    validate_graph(operations)

    # Validate graph

    {:ok, %{}}
  end

  defp validate_graph(operations) do
    graph = :digraph.new

    Enum.each(operations, fn {name, dependencies, _operation} ->
      :digraph.add_vertex(graph, name)

      Enum.each(dependencies, fn dependency ->
        :digraph.add_vertex(graph, dependency)
        :digraph.add_edge(graph, dependency, name)
      end)
    end)

    if :digraph_utils.is_acyclic(graph) do
      :ok
    else
      raise "Cyclic Error"
    end
  end
end
