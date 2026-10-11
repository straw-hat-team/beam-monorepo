defmodule Trogon.Credo.Check.Warning.MissingUseOptionTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.MissingUseOption

  test "is inert when for_use is left as the default nil" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, options: [:queue])
    |> refute_issues()
  end

  test "is inert when options is left as the default empty list" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker)
    |> refute_issues()
  end

  test "does not report a use that passes every required option" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, queue: :default, max_attempts: 5
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue, :max_attempts])
    |> refute_issues()
  end

  test "does not report a use of a module that is not configured" do
    """
    defmodule CredoSampleModule do
      use GenServer
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> refute_issues()
  end

  test "reports every configured option when a use passes no options at all" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue, :max_attempts])
    |> assert_issues(fn issues ->
      assert length(issues) == 2

      assert Enum.map(issues, & &1.message) |> Enum.sort() == [
               "The `use MyApp.Worker` must set the `max_attempts:` option.",
               "The `use MyApp.Worker` must set the `queue:` option."
             ]
    end)
  end

  test "reports only the option a use with a single option left out" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, queue: :default
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue, :max_attempts])
    |> assert_issue(fn issue ->
      assert issue.message == "The `use MyApp.Worker` must set the `max_attempts:` option."
    end)
  end

  test "reports both options when a use with two required options passes neither" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, priority: :low
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue, :max_attempts])
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "stays silent on a use whose options are a module attribute" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, @worker_opts
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> refute_issues()
  end

  test "stays silent on a use whose options are unquoted" do
    """
    defmodule MyApp.Macros do
      defmacro build(opts) do
        quote do
          use MyApp.Worker, unquote(opts)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> refute_issues()
  end

  test "stays silent on a use whose options are built with a function call" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, Keyword.merge(@base, queue: :x)
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> refute_issues()
  end

  test "stays silent on a partial keyword list with a non literal tail" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, [queue: :default | rest]
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue, :max_attempts])
    |> refute_issues()
  end

  test "accepts for_use given as a single module" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> assert_issue()
  end

  test "accepts for_use given as a list of modules" do
    """
    defmodule CredoSampleModule do
      use MyApp.OtherWorker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: [MyApp.Worker, MyApp.OtherWorker], options: [:queue])
    |> assert_issue()
  end

  test "reports a use resolved through an alias" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Worker
      use Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Worker"
      assert issue.message == "The `use MyApp.Worker` must set the `queue:` option."
    end)
  end

  test "does not report an ambiguous name as the module it is written as" do
    """
    defmodule A do
      alias Vendor.Worker
      use Worker
    end

    defmodule B do
      alias MyApp.Worker
      use Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> refute_issues()
  end

  test "reports a use written with an explicit Elixir prefix" do
    """
    defmodule CredoSampleModule do
      use Elixir.MyApp.Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.MyApp.Worker"
      assert issue.message == "The `use MyApp.Worker` must set the `queue:` option."
    end)
  end

  test "reports a use written inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro __using__(_opts) do
        quote do
          use MyApp.Worker
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption, for_use: MyApp.Worker, options: [:queue])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Worker"
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker
    end
    """
    |> to_source_file()
    |> run_check(MissingUseOption,
      for_use: MyApp.Worker,
      options: [:queue],
      hint: "Set it explicitly in every worker."
    )
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The `use MyApp.Worker` must set the `queue:` option. Set it explicitly in every worker."
    end)
  end

  test "raises when a for_use entry is not a module" do
    source_file =
      """
      defmodule CredoSampleModule do
        use MyApp.Worker
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid for_use "not a module"/, fn ->
      MissingUseOption.run(source_file, for_use: "not a module", options: [:queue])
    end
  end

  test "raises when an options entry is not an atom" do
    source_file =
      """
      defmodule CredoSampleModule do
        use MyApp.Worker
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid options "queue"/, fn ->
      MissingUseOption.run(source_file, for_use: MyApp.Worker, options: ["queue"])
    end
  end

  test "raises when a for_use list contains an entry that is not a module" do
    source_file =
      """
      defmodule CredoSampleModule do
        use MyApp.Worker
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid for_use "MyApp.Worker"/, fn ->
      MissingUseOption.run(source_file, for_use: [MyApp.Worker, "MyApp.Worker"], options: [:queue])
    end
  end

  test "raises when options is given as a bare value instead of a list" do
    source_file =
      """
      defmodule CredoSampleModule do
        use MyApp.Worker
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid options :queue/, fn ->
      MissingUseOption.run(source_file, for_use: MyApp.Worker, options: :queue)
    end
  end
end
