defmodule Trogon.Credo.Check.Warning.OpentelemetryTaskPropagation do
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
      OpenTelemetry context of the process that started it, since that context
      lives in the caller's process dictionary and a new process starts with an
      empty one. A span created inside the task then has no parent, so it shows
      up as its own disconnected trace instead of as part of the request that
      spawned it.

      `opentelemetry_process_propagator` fixes that with
      `OpentelemetryProcessPropagator.Task`, a complete drop-in for `Task` that
      copies the caller's context into the spawned process, and
      `OpentelemetryProcessPropagator.Task.Supervisor`, the same for
      `Task.Supervisor`. Use this check to flag calls to `Task` and
      `Task.Supervisor` so a project adopts the propagator everywhere instead of
      only where a trace happened to look broken.

      Every call is reported, whatever the function, because the propagator
      module wraps the functions that spawn a process and `defdelegate`s the
      rest, such as `await/2`, `yield/2`, and `shutdown/2`, straight to `Task`
      and `Task.Supervisor`. A call such as `Task.await/1` is reported even
      though awaiting a task does not spawn a process, and the fix is to call
      it through the preferred module too, not to disable the check.

      A project can prefer a module of its own instead of the propagator
      directly, such as a `MyApp.Task` that picks its implementation at compile
      time with `Application.compile_env/3` and `defdelegate`s to it. Set the
      `task` and, for `Task.Supervisor`, the `task_supervisor` param to that
      module. Once either param names a module other than the default, a call
      to the corresponding propagator module is reported too, pointing at the
      project module, so that code is not left calling the propagator directly
      once a project wraps it. A `defdelegate` whose `to:` names `Task`,
      `Task.Supervisor`, or the propagator module is not a call to it, so the
      preferred module itself is not reported for delegating.

      `Trogon.Credo.Check.Warning.PreferredModule` ships with the same
      `Task`/`OpentelemetryProcessPropagator.Task` pair in its default
      `modules` param. A project that enables this check should override that
      one's `modules` to drop the pair, so a call is not reported twice.

      Aliases are collected for the whole file rather than per lexical scope,
      so a module that aliases the preferred module suppresses findings across
      the entire file. An `alias` written inside a `quote` block is the
      exception: it takes effect wherever the macro expands, so it is not
      collected.

      Typespecs are not reported, since naming `Task` or `Task.Supervisor` in a
      `@spec` or a `@type` is not a call to it.

      A module written with an explicit `Elixir.` prefix, such as
      `Elixir.Task`, names the same module as `Task` and is reported the same
      way.

      Naming the module in an `alias`, `import`, or `require` is not a call to
      it, so directives are never reported. That includes the multi alias form
      `Task.{Supervisor}`, which shares its AST shape with a function call.

      This check was originally described by David Bernheisel.
      """,
      params: [
        task: "The module to call instead of `Task`.",
        task_supervisor: "The module to call instead of `Task.Supervisor`."
      ]
    ]

  alias Trogon.Credo.ModuleCallMatcher
  alias Trogon.Credo.ModuleName

  @default_task OpentelemetryProcessPropagator.Task
  @default_task_supervisor OpentelemetryProcessPropagator.Task.Supervisor

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    task = Params.get(params, :task, __MODULE__)
    task_supervisor = Params.get(params, :task_supervisor, __MODULE__)
    pairs = pairs_for(task, task_supervisor)
    issue_meta = IssueMeta.for(source_file, params)
    ModuleCallMatcher.run(source_file, pairs, &issue_for(issue_meta, &1, &2, &3, &4))
  end

  defp pairs_for(task, task_supervisor) do
    task = ModuleName.full(task)
    task_supervisor = ModuleName.full(task_supervisor)

    [
      {ModuleName.full(Task), task},
      {ModuleName.full(Task.Supervisor), task_supervisor}
    ]
    |> add_propagator_pair(ModuleName.full(@default_task), task)
    |> add_propagator_pair(ModuleName.full(@default_task_supervisor), task_supervisor)
  end

  defp add_propagator_pair(pairs, default, default), do: pairs
  defp add_propagator_pair(pairs, default, preferred), do: [{default, preferred} | pairs]

  defp issue_for(issue_meta, {_discouraged, preferred}, trigger, function, meta) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}.#{function}` loses the OpenTelemetry context of the caller; " <>
          "use `#{preferred}` instead.",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
