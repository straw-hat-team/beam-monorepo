defmodule Trogon.Outbox.ObanPro.ObanInstance do
  @moduledoc false

  alias Trogon.Outbox.ObanPro.TestRepo

  @doc """
  Starts a real Oban Pro instance with `testing: :disabled` under a unique name
  unless one is given, and stops it when the test exits.
  """
  @spec start!(keyword()) :: {pid(), atom()}
  def start!(opts) do
    name = Keyword.get(opts, :name, :"oban_pro_#{System.unique_integer([:positive])}")

    default = [
      name: name,
      repo: TestRepo,
      engine: Oban.Pro.Engine,
      notifier: Oban.Notifiers.Postgres,
      testing: :disabled
    ]

    {:ok, pid} = Oban.start_link(Keyword.merge(default, opts))

    ExUnit.Callbacks.on_exit(fn -> stop_quietly(pid) end)

    {pid, name}
  end

  @doc "Starts a standalone plugin against the config of the Oban instance `name`."
  @spec start_plugin!(module(), atom(), keyword()) :: pid()
  def start_plugin!(plugin, name, opts) do
    {:ok, pid} =
      plugin.start_link(Keyword.merge([name: :"#{name}_#{inspect(plugin)}", conf: Oban.config(name)], opts))

    ExUnit.Callbacks.on_exit(fn -> stop_quietly(pid) end)

    pid
  end

  @doc "Blocks until the notifier is listening, so queue signals are not dropped."
  @spec await_notifier!(atom()) :: :ok
  def await_notifier!(name) do
    Trogon.Outbox.ObanPro.Jobs.wait_until(fn -> Oban.Notifier.status(name) in [:solitary, :clustered] end, 15_000)
    :ok
  end

  @doc """
  Blocks until the producer row for `queue` exists, so jobs inserted into a
  partitioned queue are assigned a partition key.
  """
  @spec await_producer!(atom(), atom()) :: :ok
  def await_producer!(name, queue) do
    Trogon.Outbox.ObanPro.Jobs.wait_until(fn ->
      TestRepo.query!("SELECT 1 FROM public.oban_producers WHERE name = $1 AND queue = $2", [
        to_string(name),
        to_string(queue)
      ]).num_rows > 0
    end)

    :ok
  end

  defp stop_quietly(pid) do
    GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end
end
