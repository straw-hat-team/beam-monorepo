defmodule Trogon.Credo.Check.OpenTelemetry.TaskPropagationTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.OpenTelemetry.TaskPropagation

  test "reports a call to Task" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.async(fn -> :done end)
      end
    end
    """
    |> to_source_file()
    |> run_check(TaskPropagation)
    |> assert_issue(fn issue ->
      assert issue.check == TaskPropagation
      assert issue.category == TaskPropagation.category()
      assert issue.trigger == "Task"

      assert issue.message ==
               "Call `OpentelemetryProcessPropagator.Task` instead of `Task`, " <>
                 "so the OpenTelemetry context of the caller reaches the process it starts."
    end)
  end

  test "reports a call to Task.Supervisor" do
    """
    defmodule CredoSampleModule do
      def run(supervisor) do
        Task.Supervisor.async_nolink(supervisor, fn -> :done end)
      end
    end
    """
    |> to_source_file()
    |> run_check(TaskPropagation)
    |> assert_issue(fn issue -> assert issue.message =~ "OpentelemetryProcessPropagator.Task.Supervisor" end)
  end

  test "does not report a call to the propagator" do
    """
    defmodule CredoSampleModule do
      def run do
        OpentelemetryProcessPropagator.Task.async(fn -> :done end)
      end
    end
    """
    |> to_source_file()
    |> run_check(TaskPropagation)
    |> refute_issues()
  end

  test "points at the project's own modules when task and task_supervisor are set" do
    """
    defmodule CredoSampleModule do
      def run(supervisor) do
        Task.async(fn -> :done end)
        Task.Supervisor.async_nolink(supervisor, fn -> :done end)
      end
    end
    """
    |> to_source_file()
    |> run_check(TaskPropagation, task: MyApp.Task, task_supervisor: MyApp.TaskSupervisor)
    |> assert_issues(fn issues ->
      messages = issues |> Enum.sort_by(& &1.line_no) |> Enum.map(& &1.message)

      assert [
               "Call `MyApp.Task` instead of `Task`" <> _,
               "Call `MyApp.TaskSupervisor` instead of `Task.Supervisor`" <> _
             ] = messages
    end)
  end
end
