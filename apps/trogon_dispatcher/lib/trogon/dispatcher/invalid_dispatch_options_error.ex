defmodule Trogon.Dispatcher.InvalidDispatchOptionsError do
  @moduledoc """
  Raised, or returned by `Trogon.Dispatcher.DispatchOptions.new/1`, when dispatch options fail a validation.

  `validation` names the validation that failed, the way an `Ecto.Changeset` error does, and `field` the option it
  failed on.
  """

  @type validation :: :unknown_key | :duplicate_key

  defexception [:field, :value, :validation]

  @type t :: %__MODULE__{
          field: atom(),
          value: term(),
          validation: validation()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      field: Keyword.fetch!(opts, :field),
      value: Keyword.get(opts, :value),
      validation: Keyword.fetch!(opts, :validation)
    }
  end

  @impl Exception
  def message(%__MODULE__{validation: :unknown_key} = exception) do
    "unknown dispatch option #{inspect(exception.field)}, expected one of: " <>
      ":message_id, :correlation_id, :causation_id, :actor, :assigns"
  end

  def message(%__MODULE__{validation: :duplicate_key} = exception) do
    "dispatch option #{inspect(exception.field)} given more than once, got: #{inspect(exception.value)}"
  end
end
