defmodule Trogon.Credo.Check.Warning.PreferredModuleTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.PreferredModule

  test "does not report code that does not call the discouraged module" do
    """
    defmodule CredoSampleModule do
      def run do
        Enum.map([1, 2, 3], & &1)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task}])
    |> refute_issues()
  end

  test "reports a call to the discouraged module" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.start_link(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Task"
      assert issue.message == "Use `MyApp.Task` instead of `Task`."
    end)
  end

  test "does not report a call to the preferred module" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Task.start_link(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task}])
    |> refute_issues()
  end

  test "uses a custom message when configured" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.start_link(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task, "Use MyApp.Task to keep OTel context."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Use MyApp.Task to keep OTel context."
    end)
  end

  test "does not report a call site that aliases the preferred module" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Task

      def run do
        Task.start_link(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task}])
    |> refute_issues()
  end

  test "aliasing the top-level module resolves a nested reference to the preferred nested module" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Task

      def run do
        Task.Supervisor.async_nolink(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule,
      modules: [
        {Task, MyApp.Task},
        {Task.Supervisor, MyApp.Task.Supervisor}
      ]
    )
    |> refute_issues()
  end

  test "aliasing only the nested module still reports the top-level module" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Task.Supervisor

      def run do
        Task.Supervisor.start_link(name: Foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule,
      modules: [
        {Task, MyApp.Task},
        {Task.Supervisor, MyApp.Task.Supervisor}
      ]
    )
    |> assert_issue(fn issue ->
      assert issue.trigger == "Task.Supervisor"
      assert issue.message == "Use `MyApp.Task.Supervisor` instead of `Task.Supervisor`."
    end)
  end

  test "aliasing only the nested module resolves a bare reference to it" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Task.Supervisor

      def run do
        Supervisor.start_link(name: Foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule,
      modules: [
        {Task, MyApp.Task},
        {Task.Supervisor, MyApp.Task.Supervisor}
      ]
    )
    |> refute_issues()
  end

  test "an as: rename is honored and only silences the renamed identifier" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Task, as: MyAppTask

      def run do
        MyAppTask.async(fn -> :ok end)
        Task.async(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Task"
      assert issue.message == "Use `MyApp.Task` instead of `Task`."
    end)
  end

  test "alias position in the file does not matter" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.start_link(fn -> :ok end)
      end

      alias MyApp.Task
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule, modules: [{Task, MyApp.Task}])
    |> refute_issues()
  end

  test "does not report with the default modules param when not using Task" do
    """
    defmodule CredoSampleModule do
      def run do
        Enum.map([1, 2, 3], & &1)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule)
    |> refute_issues()
  end

  test "flags Task with the default modules param" do
    """
    defmodule CredoSampleModule do
      def run do
        Task.start_link(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule)
    |> assert_issue(fn issue ->
      assert issue.message == "Use `OpentelemetryProcessPropagator.Task` instead of `Task`."
    end)
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
    |> run_check(PreferredModule)
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
    |> run_check(PreferredModule)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.Task"
      assert issue.message == "Use `OpentelemetryProcessPropagator.Task` instead of `Task`."
    end)
  end

  test "does not report a multi alias naming the discouraged module" do
    """
    defmodule MyApp.Runner do
      alias Task.{Supervisor}

      def call, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule)
    |> refute_issues()
  end

  test "does not report a require or an import naming the discouraged module" do
    """
    defmodule MyApp.Runner do
      import Task
      require Task

      def call, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PreferredModule)
    |> refute_issues()
  end
end
