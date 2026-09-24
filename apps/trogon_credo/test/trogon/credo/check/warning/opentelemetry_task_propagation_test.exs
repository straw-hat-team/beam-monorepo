defmodule Trogon.Credo.Check.Warning.OpentelemetryTaskPropagationTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.OpentelemetryTaskPropagation

  test "does not report code that does not call Task or Task.Supervisor" do
    """
    defmodule CredoSampleModule do
      def run do
        Enum.map([1, 2, 3], & &1)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> refute_issues()
  end

  test "reports a call that spawns a process" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Task"

      assert issue.message ==
               "`Task.async` loses the OpenTelemetry context of the caller; " <>
                 "use `OpentelemetryProcessPropagator.Task` instead."
    end)
  end

  test "reports a call that does not spawn a process" do
    """
    defmodule CredoSampleModule do
      def run(task) do
        Task.await(task)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> assert_issue(fn issue ->
      assert issue.message ==
               "`Task.await` loses the OpenTelemetry context of the caller; " <>
                 "use `OpentelemetryProcessPropagator.Task` instead."
    end)
  end

  test "reports a call to Task.Supervisor" do
    """
    defmodule CredoSampleModule do
      def run(supervisor) do
        Task.Supervisor.async_nolink(supervisor, fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Task.Supervisor"

      assert issue.message ==
               "`Task.Supervisor.async_nolink` loses the OpenTelemetry context of the caller; " <>
                 "use `OpentelemetryProcessPropagator.Task.Supervisor` instead."
    end)
  end

  test "does not report a call to the preferred module" do
    """
    defmodule CredoSampleModule do
      def run do
        OpentelemetryProcessPropagator.Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> refute_issues()
  end

  test "points a Task call at a project's own module when task is configured" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation, task: MyApp.Task)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Task"

      assert issue.message ==
               "`Task.async` loses the OpenTelemetry context of the caller; use `MyApp.Task` instead."
    end)
  end

  test "reports a direct call to the propagator module when task is configured" do
    """
    defmodule CredoSampleModule do
      def run do
        OpentelemetryProcessPropagator.Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation, task: MyApp.Task)
    |> assert_issue(fn issue ->
      assert issue.trigger == "OpentelemetryProcessPropagator.Task"

      assert issue.message ==
               "`OpentelemetryProcessPropagator.Task.async` loses the OpenTelemetry context of " <>
                 "the caller; use `MyApp.Task` instead."
    end)
  end

  test "points a Task.Supervisor call at a project's own module when task_supervisor is configured" do
    """
    defmodule CredoSampleModule do
      def run(supervisor) do
        Task.Supervisor.async_nolink(supervisor, fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation, task_supervisor: MyApp.TaskSupervisor)
    |> assert_issue(fn issue ->
      assert issue.message ==
               "`Task.Supervisor.async_nolink` loses the OpenTelemetry context of the caller; " <>
                 "use `MyApp.TaskSupervisor` instead."
    end)
  end

  test "does not report a wrapper module that picks its implementation and delegates to it" do
    """
    defmodule MyApp.Task do
      @implementation Application.compile_env(:my_app, :task, OpentelemetryProcessPropagator.Task)

      defdelegate async(fun), to: @implementation
      defdelegate await(task), to: Task
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation, task: MyApp.Task)
    |> refute_issues()
  end

  test "does not report a call site that aliases the preferred module" do
    """
    defmodule CredoSampleModule do
      alias OpentelemetryProcessPropagator.Task

      def run do
        Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> refute_issues()
  end

  test "does not report a call site that aliases a project's own preferred module" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Task

      def run do
        Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation, task: MyApp.Task)
    |> refute_issues()
  end

  test "does not report the discouraged module named in a typespec" do
    """
    defmodule CredoSampleModule do
      @type job :: Task.t()

      @spec run(Task.t()) :: :ok
      def run(_task), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> refute_issues()
  end

  test "does not report a require or an import naming Task" do
    """
    defmodule MyApp.Runner do
      import Task
      require Task

      def call, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> refute_issues()
  end

  test "does not report a defdelegate to Task" do
    """
    defmodule MyApp.Task do
      defdelegate await(task), to: Task
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation, task: MyApp.Task)
    |> refute_issues()
  end

  test "reports a call written with an explicit Elixir prefix while the preferred module is aliased" do
    """
    defmodule CredoSampleModule do
      alias OpentelemetryProcessPropagator.Task

      def run do
        Elixir.Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(OpentelemetryTaskPropagation)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.Task"

      assert issue.message ==
               "`Elixir.Task.async` loses the OpenTelemetry context of the caller; " <>
                 "use `OpentelemetryProcessPropagator.Task` instead."
    end)
  end
end
