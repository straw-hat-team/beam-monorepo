defmodule Trogon.Outbox.TestSupport.TestPublisher do
  @moduledoc """
  An in-memory publisher that hands every batch to a handler function, which by default sends
  `{:published, tag, batch}` to the test process and acknowledges it.
  """

  @behaviour Trogon.Outbox.Publisher

  @impl Trogon.Outbox.Publisher
  def publish(batch, opts) do
    case Keyword.fetch(opts, :handler) do
      {:ok, handler} ->
        handler.(batch)

      :error ->
        send(Keyword.fetch!(opts, :test_pid), {:published, Keyword.get(opts, :tag), batch})
        :ok
    end
  end
end
