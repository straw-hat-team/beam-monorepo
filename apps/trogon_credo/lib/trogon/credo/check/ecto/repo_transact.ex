defmodule Trogon.Credo.Check.Ecto.RepoTransact do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      repos: ["**.Repo"],
      hint: nil
    ],
    explanations: [
      check: """
      `Repo.transact` lets any function open a transaction from the inside, so a
      caller cannot tell whether what it calls is transactional, or already runs
      inside a transaction of its own, without reading through it. A function that
      returns an `Ecto.Multi` says so in what it returns: the transaction is a value
      the caller composes and runs with `Repo.transaction/2`, and where it starts and
      ends is written at the call site.

      Composing an `Ecto.Multi` takes more ceremony than wrapping a function, and
      that cost is the point: a project that prefers transactionality to be
      explicit, over being convenient, keeps a single way to write a transaction.
      This check reports every call to `transact` on a repo, whatever its arity.

          # preferred
          def register(%Ecto.Multi{} = multi, changeset) do
            multi
            |> Ecto.Multi.insert(:user, changeset)
            |> Ecto.Multi.run(:welcome_email, &send_welcome_email/2)
          end

          Ecto.Multi.new()
          |> MyApp.Accounts.register(changeset)
          |> MyApp.Repo.transaction()

          # NOT preferred
          def register(changeset) do
            MyApp.Repo.transact(fn ->
              with {:ok, user} <- MyApp.Repo.insert(changeset),
                   {:ok, _email} <- send_welcome_email(user) do
                {:ok, user}
              end
            end)
          end

      A function that must run inside a transaction takes the `Ecto.Multi` as an
      argument of its own, matched as `%Ecto.Multi{} = multi`, rather than through
      its options, so a caller cannot reach it without one. A function that may run
      either way reads it from `opts[:multi]` instead.

      `Repo.transaction/1` and `Repo.transaction/2` are left alone, even though they
      accept a function as well as an `Ecto.Multi`: the argument is only known at
      runtime, and an arity says nothing about which of the two a call passes.

      A qualified call, a call through an alias, a piped call, and a capture such as
      `&MyApp.Repo.transact/2` are all reported, the way
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` reports them, since this
      check runs that one with the repos it is given.
      """,
      params: [
        repos: """
        A list of repo modules, or module name patterns given as strings, whose
        `transact` must not be called. The pattern grammar is the one
        `Trogon.Credo.Check.Design.NamespaceBoundary` documents. Defaults to
        `["**.Repo"]`, every module whose last segment is `Repo`.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall
  alias Trogon.Credo.CheckDelegate

  @message "Compose the transaction with `Ecto.Multi` and run it with `Repo.transaction/2` " <>
             "instead of calling `transact` on a repo."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    repos = params |> Params.get(:repos, __MODULE__) |> List.wrap()

    CheckDelegate.run(source_file, params, __MODULE__, ForbiddenFunctionCall,
      calls: Enum.map(repos, &forbidden_transact/1),
      except: [],
      hint: Params.get(params, :hint, __MODULE__)
    )
  end

  defp forbidden_transact(repo), do: {{repo, :transact}, @message}
end
