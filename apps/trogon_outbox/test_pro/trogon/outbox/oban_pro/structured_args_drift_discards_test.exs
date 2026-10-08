defmodule Trogon.Outbox.ObanPro.StructuredArgsDriftDiscardsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule StructuredWorker do
    @moduledoc false
    use Oban.Pro.Worker, queue: :structured, max_attempts: 3

    alias Trogon.Outbox.ObanPro.Counter

    args_schema do
      field :key, :string, required: true
      field :seq, :integer, required: true
    end

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %__MODULE__{key: key}}) do
      Counter.bump({:published, key})
      :ok
    end

    @impl Oban.Worker
    def backoff(_job), do: 0
  end

  setup do
    Jobs.truncate!()
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"structured_#{key}", queues: [structured: 1])
    %{key: to_string(key), name: name}
  end

  defp insert_raw!(args) do
    %Postgrex.Result{rows: [[id]]} =
      TestRepo.query!(
        """
        INSERT INTO public.oban_jobs (state, queue, worker, args, meta, max_attempts)
        VALUES ('available', 'structured', $1, $2, '{"structured": true}', 3)
        RETURNING id
        """,
        [inspect(StructuredWorker), args]
      )

    TestRepo.query!("SELECT pg_notify('public.oban_insert', $1)", [~s({"queue": "structured"})])
    id
  end

  defp errors(id) do
    %Postgrex.Result{rows: [[errors]]} = TestRepo.query!("SELECT errors FROM public.oban_jobs WHERE id = $1", [id])
    errors
  end

  test "a job carrying a key the worker's args_schema no longer declares is discarded without running", %{key: key} do
    id = insert_raw!(%{"key" => key, "seq" => 1, "tenant" => "removed-field"})

    Jobs.wait_until(fn -> Jobs.state(id) == "discarded" end, 10_000)

    assert Counter.get({:published, key}) == 0
    assert Enum.all?(errors(id), &(&1["error"] =~ "unexpected key"))
  end

  test "a job missing a field the worker's args_schema now requires is discarded without running", %{key: key} do
    id = insert_raw!(%{"key" => key})

    Jobs.wait_until(fn -> Jobs.state(id) == "discarded" end, 10_000)

    assert Counter.get({:published, key}) == 0
    assert Enum.all?(errors(id), &(&1["error"] =~ "can't be blank"))
  end

  test "a job whose args match the args_schema runs once", %{key: key, name: name} do
    {:ok, job} = Oban.insert(name, StructuredWorker.new(%{key: key, seq: 1}))

    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end, 10_000)

    assert Counter.get({:published, key}) == 1
  end
end
