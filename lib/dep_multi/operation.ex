defmodule DepMulti.Operation do
  @moduledoc """
  `DepMulti.Operation` is a data structure for storing a steps data.
  """

  @type changes :: map
  @type run :: (changes -> {:ok | :error, any}) | {module, atom, [any]}
  @type dependencies :: list(name)
  @type run_cmd :: {:run, run}
  @type name :: any
  @type t :: %__MODULE__{
          name: name,
          dependencies: dependencies,
          timeout: integer,
          run_cmd: run_cmd
        }

  @enforce_keys [
    :name,
    :dependencies,
    :timeout,
    :run_cmd
  ]

  defstruct [
    :name,
    :dependencies,
    :timeout,
    :run_cmd
  ]
end
