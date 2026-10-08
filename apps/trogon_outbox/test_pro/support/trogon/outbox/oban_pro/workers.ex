defmodule Trogon.Outbox.ObanPro.Workers.CounterWorker do
  @moduledoc false
  use Oban.Worker, queue: :counter, max_attempts: 1

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Counter.bump(key)
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.SlowWorker do
  @moduledoc false
  use Oban.Worker, queue: :slow, max_attempts: 3

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key, "sleep_ms" => sleep_ms}}) do
    Counter.bump({:started, key})
    Process.sleep(sleep_ms)
    Counter.bump({:finished, key})
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.UniqueWorker do
  @moduledoc false
  use Oban.Worker, queue: :unique, max_attempts: 1, unique: [period: 60]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Counter.bump(key)
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.PartitionWorker do
  @moduledoc false
  use Oban.Worker, queue: :partition, max_attempts: 1

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    inflight = Counter.bump({:inflight, key})
    Counter.max_update({:max_inflight, key}, inflight)

    Process.sleep(200)

    Counter.bump({:finish, key})
    Counter.bump({:inflight, key}, -1)
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.RetryOvertakeWorker do
  @moduledoc false
  use Oban.Worker, queue: :partition_retry, max_attempts: 3

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"role" => "predecessor"}, attempt: 1}) do
    {:error, "boom"}
  end

  def perform(%Oban.Job{args: %{"key" => key, "role" => role}}) do
    Counter.bump({:completed, key, role})
    :ok
  end

  @impl Oban.Worker
  def backoff(_job), do: 10
end

defmodule Trogon.Outbox.ObanPro.Workers.ChainDefaultWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :chain, max_attempts: 1, chain: [by: :worker]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "mode" => "slow"}}) do
    Process.sleep(2_000)
    Counter.bump({:ran, key, "slow"})
    seq = Counter.bump(:chain_seq)
    Counter.max_update({:seq_for, key}, seq)
    :ok
  end

  def process(%Oban.Job{args: %{"key" => key, "mode" => "discard"}}) do
    Counter.bump({:ran, key, "predecessor"})
    {:discard, "boom"}
  end

  def process(%Oban.Job{args: %{"key" => key, "role" => role}}) do
    Counter.bump({:ran, key, role})
    seq = Counter.bump(:chain_seq)
    Counter.max_update({:seq_for, key}, seq)
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.ChainByArgsHoldWorker do
  @moduledoc false
  use Oban.Pro.Worker,
    queue: :chain_hold,
    max_attempts: 1,
    chain: [by: [args: [:key]], on_discarded: :hold]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"mode" => "discard"}}) do
    {:discard, "boom"}
  end

  def process(%Oban.Job{args: %{"key" => key, "role" => role}}) do
    Counter.bump({:ran, key, role})
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.ChunkCrashWorker do
  @moduledoc false
  use Oban.Pro.Workers.Chunk,
    queue: :chunk_crash,
    size: 3,
    timeout: 500,
    max_attempts: 2

  alias Trogon.Outbox.ObanPro.Counter

  @impl true
  def process([%{args: %{"key" => key}} | _] = jobs) do
    for job <- jobs, do: Counter.bump({:published, key, job.args["seq"]})

    if Counter.get({:crashed, key}) == 0 do
      Counter.bump({:crashed, key})
      raise "simulated mid-chunk crash after side effects already ran for this chunk"
    end

    :ok
  end

  @impl Oban.Worker
  def backoff(_job), do: 0
end

defmodule Trogon.Outbox.ObanPro.Workers.ChunkPartialErrorWorker do
  @moduledoc false
  use Oban.Pro.Workers.Chunk,
    queue: :chunk_partial,
    size: 3,
    timeout: 500,
    max_attempts: 2

  alias Trogon.Outbox.ObanPro.Counter

  @impl true
  def process([%{args: %{"key" => key}} | _] = jobs) do
    for job <- jobs, do: Counter.bump({:ran, key, job.args["seq"]})

    case Enum.filter(jobs, &(&1.args["fail"] && &1.attempt == 1)) do
      [] -> :ok
      failing -> {:error, "boom", failing}
    end
  end

  @impl Oban.Worker
  def backoff(_job), do: 0
end

defmodule Trogon.Outbox.ObanPro.Workers.ChunkOrderWorker do
  @moduledoc """
  Only the chunk holding `seq` 1 is slow, so whichever chunk holds `seq` 2
  finishes first.
  """
  use Oban.Pro.Workers.Chunk,
    queue: :chunk_order,
    by: [args: :key],
    size: 2,
    timeout: 500

  alias Trogon.Outbox.ObanPro.Counter

  @impl true
  def process([%{args: %{"key" => key}} | _] = jobs) do
    if Enum.any?(jobs, &(&1.args["seq"] == 1)) do
      Process.sleep(400)
    end

    order = Counter.bump({:chunk_order_seq, key})

    for job <- jobs, do: Counter.max_update({:completed_order, key, job.args["seq"]}, order)

    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.BatchCallbackWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :batch, max_attempts: 1

  @behaviour Oban.Pro.Batch

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key}}) do
    Counter.bump({:batch_job_ran, key})
    :ok
  end

  @impl Oban.Pro.Batch
  def batch_completed(%Oban.Job{meta: %{"batch_id" => batch_id}}) do
    Counter.bump({:batch_completed, batch_id})
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.WorkflowWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :workflow, max_attempts: 1

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "mode" => "cancel"}, meta: %{"name" => name}}) do
    Counter.bump({:ran, key, name})
    {:cancel, "boom"}
  end

  def process(%Oban.Job{args: %{"key" => key}, meta: %{"name" => name}}) do
    Counter.bump({:ran, key, name})
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.Workers.WorkflowDiscardWorker do
  @moduledoc false
  use Oban.Worker, queue: :workflow, max_attempts: 1

  @impl Oban.Worker
  def perform(_job), do: {:discard, "boom"}
end
