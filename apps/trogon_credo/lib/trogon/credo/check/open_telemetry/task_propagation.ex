defmodule Trogon.Credo.Check.OpenTelemetry.TaskPropagation do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      task: OpentelemetryProcessPropagator.Task,
      task_supervisor: OpentelemetryProcessPropagator.Task.Supervisor
    ],
    explanations: [
      check: """
      A process started with `Task` or `Task.Supervisor` does not inherit the
      OpenTelemetry context of the process that started it, so a span created
      inside the task shows up as its own disconnected trace instead of as part of
      the request that spawned it.

      This check reports every call to `Task` and `Task.Supervisor`, pointing at
      `OpentelemetryProcessPropagator.Task` and
      `OpentelemetryProcessPropagator.Task.Supervisor`, or at the project's own
      modules when `task` and `task_supervisor` name them.

          # preferred
          OpentelemetryProcessPropagator.Task.async(fn -> MyApp.Billing.charge(order) end)

          # NOT preferred
          Task.async(fn -> MyApp.Billing.charge(order) end)

      It runs `Trogon.Credo.Check.Warning.OpentelemetryTaskPropagation` with the
      params it is given, and reports what that check documents, under its own
      name, so `Trogon.Credo.Plugin.OpenTelemetry` can enable it without touching
      an entry a project already has for that one.
      """,
      params: [
        task: "The module to call instead of `Task`.",
        task_supervisor: "The module to call instead of `Task.Supervisor`."
      ]
    ]

  alias Trogon.Credo.Check.Warning.OpentelemetryTaskPropagation
  alias Trogon.Credo.CheckDelegate

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    CheckDelegate.run(source_file, params, __MODULE__, OpentelemetryTaskPropagation,
      task: Params.get(params, :task, __MODULE__),
      task_supervisor: Params.get(params, :task_supervisor, __MODULE__)
    )
  end
end
