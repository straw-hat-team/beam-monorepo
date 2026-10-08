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
      Ecto offers more than one way to run several operations in a transaction. A
      project that settles on composing them with `Ecto.Multi` and running the result
      with `Repo.transaction/2` wants every transaction written that way, so the steps
      are named, inspectable before they run, and reported by name when one fails,
      instead of being buried in a function that `Repo.transact` happens to call.

      This check reports every call to `transact` on a repo, whatever its arity, so a
      project keeps a single way to write a transaction.

          # preferred
          Ecto.Multi.new()
          |> Ecto.Multi.insert(:user, changeset)
          |> Ecto.Multi.run(:welcome_email, &send_welcome_email/2)
          |> MyApp.Repo.transaction()

          # NOT preferred
          MyApp.Repo.transact(fn ->
            with {:ok, user} <- MyApp.Repo.insert(changeset),
                 {:ok, _email} <- send_welcome_email(user) do
              {:ok, user}
            end
          end)

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
      calls: Enum.map(repos, &{{&1, :transact}, @message}),
      except: [],
      hint: Params.get(params, :hint, __MODULE__)
    )
  end
end
