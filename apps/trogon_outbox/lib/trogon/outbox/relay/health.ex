defmodule Trogon.Outbox.Relay.Health do
  @moduledoc """
  A point-in-time read of a relay's held partitions, lag and watermark holdback, returned by
  `Trogon.Outbox.Relay.health/1`.

  `expected` is every partition this relay is configured to consume; `held` is the subset it
  currently holds the lock for. A relay missing some of `expected` from `held` for longer than a
  few `:lock_interval`s is a standby that cannot take over, worth alerting on. `lag` covers only
  partitions in `held`, since a relay cannot read a partition it does not hold.
  """

  alias Trogon.Outbox.Partition
  alias Trogon.Outbox.Relay.Lag

  @enforce_keys [:held, :expected, :lag, :watermark_holdback_ms]
  defstruct [:held, :expected, :lag, :watermark_holdback_ms]

  @type t :: %__MODULE__{
          held: [Partition.t()],
          expected: [Partition.t()],
          lag: %{Partition.t() => Lag.t()},
          watermark_holdback_ms: non_neg_integer()
        }
end
