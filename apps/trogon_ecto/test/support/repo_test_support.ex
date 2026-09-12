defmodule Trogon.Ecto.RepoTestSupport do
  @moduledoc false

  defmodule StubRepo do
    @moduledoc false
    use Trogon.Ecto.Repo

    @doc false
    @spec stub_transaction(term()) :: term()
    def stub_transaction(result), do: Process.put(__MODULE__, result)

    @doc false
    @spec transaction(Ecto.Multi.t(), Keyword.t()) :: term()
    def transaction(%Ecto.Multi{} = multi, opts) do
      send(self(), {:transaction, multi, opts})
      Process.get(__MODULE__)
    end
  end
end
