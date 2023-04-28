defmodule OnePiece.Commanded.Aggregate.StatelessLifespan do
  @moduledoc """
  Stops the aggregate after a command, event or error.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  def after_command(_command), do: :stop
  def after_event(_event), do: :stop
  def after_error(_error), do: :stop
end
