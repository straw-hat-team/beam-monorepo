defmodule Trogon.Credo.Check.Oban.ForbiddenDecorator do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [hint: nil],
    explanations: [
      check: """
      `use Oban.Pro.Decorator` turns an ordinary function into a job by decorating
      it, so the job has no module of its own: its queue, its retries, and its
      arguments live on an annotation attached to a function in some other module.
      A project that wants every job to be a worker, found by name, configured in
      one `use`, and checked by the same rules as every other worker, wants that
      shortcut left out.

      This check reports every `use Oban.Pro.Decorator`.

          # preferred
          defmodule MyApp.SendWelcomeEmailWorker do
            use Oban.Pro.Worker, queue: :mailers

            @impl Oban.Pro.Worker
            def process(%Oban.Job{args: args}), do: MyApp.Mailer.send_welcome_email(args)
          end

          # NOT preferred
          defmodule MyApp.Mailer do
            use Oban.Pro.Decorator

            @job queue: :mailers
            def send_welcome_email(args), do: deliver(args)
          end

      A `use` written through an alias is reported under the module it resolves
      to, the way `Trogon.Credo.Check.Warning.ForbiddenUse` documents, since this
      check runs that one.
      """,
      params: [
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.Check.Warning.ForbiddenUse
  alias Trogon.Credo.CheckDelegate

  @message "Define an `Oban.Pro.Worker` for the job instead of decorating a function with `Oban.Pro.Decorator`."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    message =
      case Params.get(params, :hint, __MODULE__) do
        nil -> @message
        hint -> "#{@message} #{hint}"
      end

    CheckDelegate.run(source_file, params, __MODULE__, ForbiddenUse, modules: [{Oban.Pro.Decorator, message}])
  end
end
