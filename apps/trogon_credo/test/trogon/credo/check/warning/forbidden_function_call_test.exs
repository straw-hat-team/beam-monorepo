defmodule Trogon.Credo.Check.Warning.ForbiddenFunctionCallTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall

  test "is silent when calls is left as the default empty list" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall)
    |> refute_issues()
  end

  test "does not report code that does not call a forbidden function" do
    """
    defmodule CredoSampleModule do
      def run do
        Enum.map([1, 2, 3], & &1)
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "reports a qualified call to a forbidden function on an Elixir module" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "System.get_env"
      assert issue.message == "The `System.get_env` function must not be called."
    end)
  end

  test "reports a qualified call to a forbidden function on an Erlang module" do
    """
    defmodule CredoSampleModule do
      def run do
        :os.system_time()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{:os, :system_time}])
    |> assert_issue(fn issue ->
      assert issue.trigger == ":os.system_time"
      assert issue.message == "The `:os.system_time` function must not be called."
    end)
  end

  test "reports a captured call to a forbidden function on an Elixir module" do
    """
    defmodule CredoSampleModule do
      def run do
        &System.get_env/1
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "System.get_env"
      assert issue.message == "The `System.get_env` function must not be called."
    end)
  end

  test "reports a captured call to a forbidden function on an Erlang module" do
    """
    defmodule CredoSampleModule do
      def run do
        &:os.system_time/0
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{:os, :system_time}])
    |> assert_issue(fn issue ->
      assert issue.trigger == ":os.system_time"
      assert issue.message == "The `:os.system_time` function must not be called."
    end)
  end

  test "reports a bare call to a Kernel entry" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        dbg(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "dbg"
      assert issue.message == "The `Kernel.dbg` function must not be called."
    end)
  end

  test "reports a qualified call to a Kernel entry" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        Kernel.dbg(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Kernel.dbg"
      assert issue.message == "The `Kernel.dbg` function must not be called."
    end)
  end

  test "does not report an unqualified capture of a Kernel entry" do
    """
    defmodule CredoSampleModule do
      def run do
        &dbg/1
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> refute_issues()
  end

  test "does not report a bare call to a function on a module other than Kernel" do
    """
    defmodule CredoSampleModule do
      def get_env(key), do: key

      def run do
        get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a local function definition whose name matches a Kernel entry" do
    """
    defmodule CredoSampleModule do
      def dbg(value), do: value
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> refute_issues()
  end

  test "does not report a defdelegate head whose name matches a Kernel entry" do
    """
    defmodule CredoSampleModule do
      defdelegate dbg(value), to: MyApp.Other
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> refute_issues()
  end

  test "reports a forbidden call written in the body of a definition whose head matches a Kernel entry" do
    """
    defmodule CredoSampleModule do
      def dbg(value) do
        System.get_env("HOME")
        value
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}, {System, :get_env}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "System.get_env"
    end)
  end

  test "uses a custom message when configured" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{{System, :get_env}, "Use the runtime config instead."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Use the runtime config instead."
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}], hint: "Read it from application config instead.")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The `System.get_env` function must not be called. Read it from application config instead."
    end)
  end

  test "appends the hint to a custom message" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: [{{System, :get_env}, "Use the runtime config instead."}],
      hint: "See MyApp.Config."
    )
    |> assert_issue(fn issue ->
      assert issue.message == "Use the runtime config instead. See MyApp.Config."
    end)
  end

  test "resolves a call written through an alias" do
    """
    defmodule CredoSampleModule do
      alias System, as: Env

      def run do
        Env.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Env.get_env"
      assert issue.message == "The `System.get_env` function must not be called."
    end)
  end

  test "does not report through a name the file binds to more than one module" do
    """
    defmodule A do
      alias Vendor.System

      def run, do: System.get_env("HOME")
    end

    defmodule B do
      alias MyApp.System

      def run, do: System.get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "reports a call written with an explicit Elixir prefix" do
    """
    defmodule CredoSampleModule do
      def run do
        Elixir.System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.System.get_env"
      assert issue.message == "The `System.get_env` function must not be called."
    end)
  end

  test "does not report a call to a function that is not configured" do
    """
    defmodule CredoSampleModule do
      def run do
        System.fetch_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a call to a same named function on a different module" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Env.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a module named in a @spec" do
    """
    defmodule CredoSampleModule do
      @spec run() :: System.t()
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :t}])
    |> refute_issues()
  end

  test "does not report a module named in an alias, import, require, or use directive" do
    """
    defmodule CredoSampleModule do
      alias System
      import System
      require System
      use System
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a call written inside a use directive's options" do
    """
    defmodule CredoSampleModule do
      use MyApp.Worker, retries: System.get_env("RETRIES")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a multi alias naming the forbidden module" do
    """
    defmodule CredoSampleModule do
      alias System.{Foo}

      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "reports every call to a module named on its own" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
        System.cmd("ls", [])
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["System.cmd", "System.get_env"]

      assert Enum.map(issues, & &1.message) == [
               "The `System.cmd` function must not be called.",
               "The `System.get_env` function must not be called."
             ]
    end)
  end

  test "reports every call to an Erlang module named on its own" do
    """
    defmodule CredoSampleModule do
      def run do
        :rand.uniform(3)
        :rand.bytes(4)
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [:rand])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == [":rand.bytes", ":rand.uniform"]
    end)
  end

  test "reports a captured call to a module named on its own" do
    """
    defmodule CredoSampleModule do
      def run, do: Enum.map(["HOME"], &System.get_env/1)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [:rand, System])
    |> assert_issue(fn issue ->
      assert issue.trigger == "System.get_env"
    end)
  end

  test "resolves a call through an alias for a module named on its own" do
    """
    defmodule CredoSampleModule do
      alias System, as: Env

      def run, do: Env.get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Env.get_env"
    end)
  end

  test "uses a custom message for a module named on its own" do
    """
    defmodule CredoSampleModule do
      def run, do: :rand.uniform(3)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{:rand, "Randomness belongs outside this layer."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Randomness belongs outside this layer."
    end)
  end

  test "prefers a function entry's message over that of the module it belongs to" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
        System.cmd("ls", [])
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: [{System, "Read the environment at the config boundary."}, {{System, :get_env}, "Use a runtime config."}]
    )
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.message) == [
               "Read the environment at the config boundary.",
               "Use a runtime config."
             ]
    end)
  end

  test "does not report a module named on its own outside a call position" do
    """
    defmodule CredoSampleModule do
      alias System, as: Sys

      @spec run :: System.t()
      def run, do: Sys
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> refute_issues()
  end

  test "raises when Kernel is named on its own" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: :ok
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/`Kernel` cannot be forbidden as a whole module/, fn ->
      ForbiddenFunctionCall.run(source_file, calls: [Kernel])
    end
  end

  test "raises when a calls entry is neither a module nor a {Module, :function} tuple" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: :ok
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid calls entry "System"/, fn ->
      ForbiddenFunctionCall.run(source_file, calls: ["System"])
    end
  end

  test "raises when a calls entry names an arity" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: :ok
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid calls entry {System, :get_env, 1}/, fn ->
      ForbiddenFunctionCall.run(source_file, calls: [{System, :get_env, 1}])
    end
  end
end
