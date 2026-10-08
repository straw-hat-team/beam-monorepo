defmodule Trogon.Outbox.Relay.Lag do
  @moduledoc """
  How far a relay's cursor on one partition trails the snapshot watermark: how many events below
  the watermark it has not published yet, and how long the oldest of them has been waiting.

  `oldest_event_age_ms` is `0` when `count` is `0`; there is no event to measure the age of.
  """

  @enforce_keys [:count, :oldest_event_age_ms]
  defstruct [:count, :oldest_event_age_ms]

  @type t :: %__MODULE__{count: non_neg_integer(), oldest_event_age_ms: non_neg_integer()}
end
