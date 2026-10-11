defmodule Trogon.Test.Expectation do
  @moduledoc false

  @spec times(keyword()) :: non_neg_integer()
  def times(opts), do: Keyword.get(opts, :times, 1)

  @spec returns!(keyword()) :: term()
  def returns!(opts), do: Keyword.fetch!(opts, :returns)

  @spec record(pid(), module(), {atom(), [term()]}, returns) :: returns when returns: term()
  def record(owner, source, operation, returns) do
    send(owner, {Trogon.Test, {source, operation}})
    returns
  end
end
