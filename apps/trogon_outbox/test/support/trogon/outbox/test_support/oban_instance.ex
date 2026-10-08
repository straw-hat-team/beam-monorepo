defmodule Trogon.Outbox.TestSupport.ObanInstance do
  @moduledoc false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanJobs

  @doc """
  Options for a real Oban instance against the test database. Staging runs
  every 50ms so retries and snoozes become available quickly, and no
  maintenance plugin runs unless a test asks for it.
  """
  @spec opts(atom(), keyword()) :: keyword()
  def opts(name, overrides \\ []) do
    Keyword.merge(
      [
        name: name,
        repo: TestRepo,
        testing: :disabled,
        stager: [interval: 50],
        queues: [],
        shutdown_grace_period: 100
      ],
      overrides
    )
  end

  @doc """
  Blocks until the notifier for `name` is receiving messages. Queue control
  functions such as `Oban.resume_queue/2` broadcast through the notifier and
  are dropped silently when called before it is listening.
  """
  @spec await_notifier!(atom()) :: :ok
  def await_notifier!(name) do
    if ObanJobs.eventually(fn -> Oban.Notifier.status(name) in [:solitary, :clustered] end) do
      :ok
    else
      raise "the notifier for #{inspect(name)} never started listening"
    end
  end
end
