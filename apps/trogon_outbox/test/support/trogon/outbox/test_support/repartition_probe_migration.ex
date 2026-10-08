defmodule Trogon.Outbox.TestSupport.RepartitionProbeMigration do
  @moduledoc """
  Runs `Trogon.Outbox.Migration.up/1` a second time against an already installed prefix, with a
  partition count a test controls, to exercise the guard against changing partitions in place.
  """

  use Ecto.Migration

  def up do
    {prefix, partitions} = :persistent_term.get(__MODULE__)
    Trogon.Outbox.Migration.up(prefix: prefix, partitions: partitions)
  end

  def down, do: :ok

  def put(prefix, partitions), do: :persistent_term.put(__MODULE__, {prefix, partitions})
end
