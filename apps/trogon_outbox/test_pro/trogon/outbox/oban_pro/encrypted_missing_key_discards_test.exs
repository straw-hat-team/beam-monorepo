defmodule Trogon.Outbox.ObanPro.EncryptedMissingKeyDiscardsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule Keyring do
    @moduledoc false
    @behaviour Oban.Pro.Keyring

    @impl Oban.Pro.Keyring
    def current_key do
      id = :persistent_term.get({__MODULE__, :current}, "k1")
      {id, key(id)}
    end

    @impl Oban.Pro.Keyring
    def fetch_key(id) do
      if id in :persistent_term.get({__MODULE__, :known}, ["k1"]), do: {:ok, key(id)}, else: :error
    end

    def configure!(current, known) do
      :persistent_term.put({__MODULE__, :current}, current)
      :persistent_term.put({__MODULE__, :known}, known)
    end

    defp key(id), do: Base.encode64(:crypto.hash(:sha256, id))
  end

  defmodule EncryptedWorker do
    @moduledoc false
    use Oban.Pro.Worker,
      queue: :encrypted,
      max_attempts: 1,
      encrypted: [keyring: Trogon.Outbox.ObanPro.EncryptedMissingKeyDiscardsTest.Keyring]

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %{"key" => key}}) do
      Counter.bump({:published, key})
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    Keyring.configure!("k1", ["k1"])
    on_exit(fn -> Keyring.configure!("k1", ["k1"]) end)
    :ok
  end

  defp row(id) do
    %Postgrex.Result{rows: [[state, args, errors]]} =
      TestRepo.query!("SELECT state, args, errors FROM public.oban_jobs WHERE id = $1", [id])

    %{state: state, args: args, errors: errors}
  end

  test "a job encrypted with a key that was dropped from the keyring is discarded without running, and its args stay unreadable" do
    key = System.unique_integer([:positive])
    name = :"encrypted_dropped_#{key}"
    {_pid, ^name} = ObanInstance.start!(name: name, queues: [])

    {:ok, job} = Oban.insert(name, EncryptedWorker.new(%{"key" => key}))
    refute Map.has_key?(row(job.id).args, "key")

    Keyring.configure!("k2", ["k2"])
    {_runner, runner} = ObanInstance.start!(name: :"#{name}_runner", queues: [encrypted: 1])
    :ok = ObanInstance.await_producer!(runner, :encrypted)

    Jobs.wait_until(fn -> row(job.id).state == "discarded" end, 10_000)

    %{args: args, errors: errors} = row(job.id)
    assert Counter.get({:published, key}) == 0
    assert Map.keys(args) == ["data"]
    assert length(errors) == 1
    assert Enum.all?(errors, &(&1["error"] =~ "k1"))
  end

  test "a discarded job runs once its key is back in the keyring and the job is retried" do
    key = System.unique_integer([:positive])
    name = :"encrypted_restored_#{key}"
    {_pid, ^name} = ObanInstance.start!(name: name, queues: [])

    {:ok, job} = Oban.insert(name, EncryptedWorker.new(%{"key" => key}))

    Keyring.configure!("k2", ["k2"])
    {_runner, runner} = ObanInstance.start!(name: :"#{name}_runner", queues: [encrypted: 1])
    :ok = ObanInstance.await_producer!(runner, :encrypted)
    Jobs.wait_until(fn -> row(job.id).state == "discarded" end, 10_000)

    Keyring.configure!("k2", ["k1", "k2"])
    :ok = Oban.retry_job(runner, job.id)

    Jobs.wait_until(fn -> row(job.id).state == "completed" end, 10_000)
    assert Counter.get({:published, key}) == 1
  end
end
