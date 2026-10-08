defmodule Trogon.Outbox.Publisher do
  @moduledoc """
  A broker the relay publishes batches to.

  Return `:ok` only once the broker has acknowledged every event in the batch. Any other result,
  or a raise, leaves the cursor where it was and the relay retries the same batch later, so a
  publisher must tolerate replays. Each event carries `Trogon.Outbox.Event.message_id/1` for the
  broker or consumer to deduplicate on, and its source as the ordering key.

  A publisher that rejects payloads above a size implements `limits/1`, returning a
  `Trogon.Outbox.Publisher.Limits.t()` built from the same options `publish/2` is called with, so
  `Trogon.Outbox.append/4` can pass the identical `Limits.t()` and refuse an oversized payload
  before it ever commits, instead of handing the publisher an event it will never deliver.
  """

  alias Trogon.Outbox.Batch
  alias Trogon.Outbox.Publisher.Limits

  @callback publish(Batch.t(), opts :: keyword()) :: :ok | {:error, term()}
  @callback limits(opts :: keyword()) :: Limits.t()

  @optional_callbacks limits: 1
end
