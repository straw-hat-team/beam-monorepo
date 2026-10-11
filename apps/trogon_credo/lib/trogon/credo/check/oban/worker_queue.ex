defmodule Trogon.Credo.Check.Oban.WorkerQueue do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      for_use: [Oban.Worker, Oban.Pro.Worker],
      hint: nil
    ],
    explanations: [
      check: """
      `use Oban.Worker` without a `queue:` option puts the worker's jobs in the
      `default` queue. That compiles and runs, and it is decided once and then
      forgotten: the job shares its concurrency limit with every other worker that
      forgot too, and moving it to a queue of its own later means jobs already
      inserted keep running where they were enqueued.

      This check reports a `use` of a worker module that does not pass `queue:`, so
      every worker states the queue it runs in.

          # preferred
          defmodule MyApp.SendWelcomeEmailWorker do
            use Oban.Worker, queue: :mailers
          end

          # NOT preferred
          defmodule MyApp.SendWelcomeEmailWorker do
            use Oban.Worker
          end

      Options are inspected only when written as a keyword list literal, and a
      `use` written through an alias is reported under the module it resolves to,
      the way `Trogon.Credo.Check.Warning.MissingUseOption` documents, since this
      check runs that one with the worker modules it is given.
      """,
      params: [
        for_use: """
        A list of worker modules whose `use` must pass `queue:`. Defaults to
        `[Oban.Worker, Oban.Pro.Worker]`. A project that wraps them in a worker
        module of its own lists that module here.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.Check.Warning.MissingUseOption
  alias Trogon.Credo.CheckDelegate

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    CheckDelegate.run(source_file, params, __MODULE__, MissingUseOption,
      for_use: params |> Params.get(:for_use, __MODULE__) |> List.wrap(),
      options: [:queue],
      hint: Params.get(params, :hint, __MODULE__)
    )
  end
end
