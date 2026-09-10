defmodule Trogon.Ecto.MigrationTestSupport do
  @moduledoc false

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Ecto.Migration.Runner
  alias Ecto.Migration.Table

  defmodule StandardMigration do
    @moduledoc false
    use Trogon.Ecto.Migration
  end

  defmodule NoTransactionMigration do
    @moduledoc false
    use Trogon.Ecto.Migration, mode: :no_transaction
  end

  defmodule ConcurrentMigration do
    @moduledoc false
    use Trogon.Ecto.Migration, mode: :concurrent
  end

  @doc false
  @spec start_migration_runner() :: %{runner: pid(), table: Table.t()}
  def start_migration_runner do
    {:ok, runner} =
      Runner.start_link({self(), __MODULE__, [], __MODULE__, :forward, :up, %{level: false, sql: false}})

    Runner.metadata(runner, [])

    on_exit(fn ->
      if Process.alive?(runner), do: Agent.stop(runner)
    end)

    %{runner: runner, table: %Table{name: "accounts"}}
  end

  @doc false
  @spec capture_command(pid(), Table.t(), (-> term())) :: tuple()
  def capture_command(runner, table, fun) do
    Runner.start_command({:alter, table})
    fun.()
    Runner.end_command()
    [command] = Agent.get(runner, & &1.commands)
    command
  end
end
