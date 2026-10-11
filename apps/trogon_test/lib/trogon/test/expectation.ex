defmodule Trogon.Test.Expectation do
  @moduledoc false

  alias Trogon.Test.Recorder

  @spec times(keyword()) :: non_neg_integer()
  def times(opts), do: Keyword.get(opts, :times, 1)

  @spec returns!(keyword()) :: term()
  def returns!(opts), do: Keyword.fetch!(opts, :returns)

  @spec returns!(keyword(), (term() -> boolean()), String.t()) :: term()
  def returns!(opts, accepts?, expected) do
    opts
    |> returns!()
    |> accept!(accepts?, expected)
  end

  @spec accept!(value, (term() -> boolean()), String.t()) :: value when value: term()
  def accept!(value, accepts?, expected) do
    if accepts?.(value) do
      value
    else
      raise ArgumentError, "expected :returns to be #{expected}, got: #{inspect(value)}"
    end
  end

  @spec record(Recorder.t(), module(), {atom(), [term()]}, returns) :: returns when returns: term()
  def record(recorder, source, operation, returns) do
    Recorder.record(recorder, {Trogon.Test, {source, operation}})
    returns
  end
end
