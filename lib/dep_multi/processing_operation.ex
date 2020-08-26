defmodule DepMulti.ProcessingOperation do
  @moduledoc """
  `DepMulti.ProcessingOperation` is a data structure for storing a steps data.
  """

  @type t :: %__MODULE__{
          runner_pid: pid(),
          operation: DepMulti.Operation.t(),
          timer_pid: pid(),
          timeout_ref: reference()
        }

  @enforce_keys [
    :runner_pid,
    :operation
  ]

  defstruct [
    :runner_pid,
    :operation,
    :timer_pid,
    :timeout_ref
  ]
end
