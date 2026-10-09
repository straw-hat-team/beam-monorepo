defmodule Trogon.Dispatcher.InvalidDispatchOptionsError do
  @moduledoc """
  Raised, or returned by `Trogon.Dispatcher.DispatchOptions.new/1`, when dispatch options break an invariant.

  Options are checked where they are built and again when a dispatch starts, so a bad value fails at the caller rather
  than inside whichever middleware first touches it.
  """

  @type reason :: :not_a_keyword | :unknown_key | :not_a_map | :non_atom_key

  defexception [:field, :value, :reason]

  @type t :: %__MODULE__{
          field: atom() | nil,
          value: term(),
          reason: reason()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      field: Keyword.get(opts, :field),
      value: Keyword.get(opts, :value),
      reason: Keyword.fetch!(opts, :reason)
    }
  end

  @impl Exception
  def message(%__MODULE__{reason: :not_a_keyword} = exception) do
    "expected dispatch options as a keyword list, got: #{inspect(exception.value)}"
  end

  def message(%__MODULE__{reason: :unknown_key} = exception) do
    "unknown dispatch option #{inspect(exception.field)}, expected one of: " <>
      ":message_id, :correlation_id, :causation_id, :actor, :assigns"
  end

  def message(%__MODULE__{reason: :not_a_map} = exception) do
    "expected dispatch option #{inspect(exception.field)} to be a map, got: #{inspect(exception.value)}"
  end

  def message(%__MODULE__{reason: :non_atom_key} = exception) do
    "expected every key in dispatch option #{inspect(exception.field)} to be an atom, got: #{inspect(exception.value)}"
  end
end
