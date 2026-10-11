defmodule Trogon.Commanded.Aggregate.StatelessLifespan do
  @moduledoc """
  Stops the aggregate after a command, event or error.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  @doc """
  Stops the aggregate after a command.
      iex> Trogon.Commanded.Aggregate.StatelessLifespan.after_command(%MyCommandOne{})
      :stop
  """
  def after_command(_command), do: :stop

  @doc """
  Stops the aggregate after an event.
      iex> Trogon.Commanded.Aggregate.StatelessLifespan.after_event(%DepositAccountOpened{})
      :stop
  """
  def after_event(_event), do: :stop

  @doc """
  Stops the aggregate after an error.
      iex> Trogon.Commanded.Aggregate.StatelessLifespan.after_error({:error, :something_happened})
      :stop
  """
  def after_error(_error), do: :stop
end
