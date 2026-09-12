defmodule Trogon.Ecto.Repo do
  @moduledoc """
  Extends a repo with the transaction helpers this package provides.

      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
        use Trogon.Ecto.Repo
      end

  What it adds is documented on your own repo, since that is where the functions
  end up.
  """

  defmacro __using__(_opts) do
    quote do
      @doc """
      Runs an `Ecto.Multi` and reports a failure as the value that failed.

          Ecto.Multi.new()
          |> Ecto.Multi.insert(:account, account_changeset)
          |> Ecto.Multi.insert(:profile, profile_changeset)
          |> MyApp.Repo.transact_result()

      `c:Ecto.Repo.transaction/2` reports a failed multi as
      `{:error, failed_operation, failed_value, changes_so_far}`. A caller that
      only wants to render the changeset that failed has to reach into four
      elements to find it, and a caller handing the result upward has to reshape
      it before anything expecting `{:ok, _}` or `{:error, _}` can match, which
      is most things, including `with`.

      `opts` are the options of `c:Ecto.Repo.transaction/2` and mean the same
      here.

      Use `c:Ecto.Repo.transaction/2` when the operation name is what you need,
      such as telling two failed inserts apart, since this discards it along
      with the changes made before the failure.
      """
      @spec transact_result(Ecto.Multi.t(), Keyword.t()) ::
              {:ok, Ecto.Multi.changes()} | {:error, any()}
      def transact_result(%Ecto.Multi{} = multi, opts \\ []) do
        case transaction(multi, opts) do
          {:ok, changes} -> {:ok, changes}
          {:error, _failed_operation, failed_value, _changes_so_far} -> {:error, failed_value}
        end
      end
    end
  end
end
