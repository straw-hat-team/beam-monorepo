defmodule Trogon.Credo.Check.Readability.RequiredUseTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.RequiredUse

  test "is inert when modules is left as the default empty list" do
    """
    defmodule MyApp.Processor.SendEmail do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse)
    |> refute_issues()
  end

  test "does not report a module that uses the configured module" do
    """
    defmodule MyApp.Processor.SendEmail do
      use MyApp.Worker
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> refute_issues()
  end

  test "reports a module missing the required use" do
    """
    defmodule MyApp.Processor.SendEmail do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> assert_issue(fn issue ->
      assert issue.message == "A module in this directory must `use MyApp.Worker`."
    end)
  end

  test "does not report a module that uses the second of two configured modules" do
    """
    defmodule MyApp.Processor.SendEmail do
      use MyApp.EventHandler
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker, MyApp.EventHandler])
    |> refute_issues()
  end

  test "reports a module matching none of several configured modules with the plural message" do
    """
    defmodule MyApp.Processor.SendEmail do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker, MyApp.EventHandler])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "A module in this directory must use one of these modules: `MyApp.Worker`, `MyApp.EventHandler`."
    end)
  end

  test "reports a module whose name is not written as an alias with no trigger" do
    """
    defmodule Module.concat(MyApp, SendEmail) do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> assert_issue(fn issue ->
      assert issue.message == "A module in this directory must `use MyApp.Worker`."
      assert issue.trigger == Credo.Issue.no_trigger()
    end)
  end

  test "does not report a file that defines no module at all" do
    """
    defimpl Enumerable, for: MyApp.Collection do
    end
    """
    |> to_source_file("lib/my_app/collection_impl.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> refute_issues()
  end

  test "reports a file whose only use is inside a quote block" do
    """
    defmodule MyApp.Processor.Builder do
      defmacro build do
        quote do
          use MyApp.Worker
        end
      end
    end
    """
    |> to_source_file("lib/my_app/processor/builder.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> assert_issue()
  end

  test "does not report a use written through an alias" do
    """
    defmodule MyApp.Processor.SendEmail do
      alias MyApp.Worker

      use Worker
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> refute_issues()
  end

  test "reports a use written through an ambiguous alias" do
    """
    defmodule MyApp.Processor do
      defmodule First do
        alias MyApp.Worker
      end

      defmodule Second do
        alias MyApp.OtherWorker, as: Worker
      end

      use Worker
    end
    """
    |> to_source_file("lib/my_app/processor.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> assert_issue()
  end

  test "does not report a use written with an explicit Elixir prefix" do
    """
    defmodule MyApp.Processor.SendEmail do
      use Elixir.MyApp.Worker
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> refute_issues()
  end

  test "is satisfied by a nested module carrying the use" do
    """
    defmodule MyApp.Processor.SendEmail do
      defmodule Options do
        use MyApp.Worker
      end
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> refute_issues()
  end

  test "does not satisfy the check with a use whose module cannot be read statically" do
    """
    defmodule MyApp.Processor.SendEmail do
      use unquote(mod)
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> assert_issue()
  end

  test "uses the outermost module's name as the trigger" do
    """
    defmodule MyApp.Processor.SendEmail do
      defmodule Options do
      end
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Processor.SendEmail" end)
  end

  test "replaces the default message with a custom message" do
    """
    defmodule MyApp.Processor.SendEmail do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker], message: "Bring in the shared worker behaviour.")
    |> assert_issue(fn issue ->
      assert issue.message == "Bring in the shared worker behaviour."
    end)
  end

  test "appends the hint to the default message" do
    """
    defmodule MyApp.Processor.SendEmail do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse, modules: [MyApp.Worker], hint: "Add `use MyApp.Worker`.")
    |> assert_issue(fn issue ->
      assert issue.message == "A module in this directory must `use MyApp.Worker`. Add `use MyApp.Worker`."
    end)
  end

  test "appends the hint to a custom message" do
    """
    defmodule MyApp.Processor.SendEmail do
    end
    """
    |> to_source_file("lib/my_app/processor/send_email.ex")
    |> run_check(RequiredUse,
      modules: [MyApp.Worker],
      message: "Bring in the shared worker behaviour.",
      hint: "See the processor guide."
    )
    |> assert_issue(fn issue ->
      assert issue.message == "Bring in the shared worker behaviour. See the processor guide."
    end)
  end

  test "raises when a modules entry is not a module" do
    source_file =
      """
      defmodule MyApp.Processor.SendEmail do
      end
      """
      |> to_source_file("lib/my_app/processor/send_email.ex")

    assert_raise ArgumentError,
                 "invalid modules entry {MyApp.Worker, \"use it\"}: expected a module",
                 fn ->
                   RequiredUse.run(source_file, modules: [{MyApp.Worker, "use it"}])
                 end
  end
end
