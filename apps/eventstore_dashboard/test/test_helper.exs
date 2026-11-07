exclude = if EventStoreDashboard.Test.Postgres.configured?(), do: [], else: [:postgres]

ExUnit.start(exclude: exclude)
