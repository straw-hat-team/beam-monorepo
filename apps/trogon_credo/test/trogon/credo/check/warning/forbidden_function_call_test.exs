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

  test "reports a bare call to a function the file imports by name" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "get_env"
      assert issue.message == "The `System.get_env` function must not be called."
    end)
  end

  test "reports a bare call to a function the file imports without restriction" do
    """
    defmodule CredoSampleModule do
      import System

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "reports a bare call to a module named on its own when the import names the function" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "does not report a bare call to a module named on its own imported without restriction" do
    """
    defmodule CredoSampleModule do
      import System

      def run, do: build_something()
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> refute_issues()
  end

  test "resolves the module an import names through an alias" do
    """
    defmodule CredoSampleModule do
      alias System, as: Env
      import Env, only: [get_env: 1]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "does not report a bare call to a function imported from an unconfigured module" do
    """
    defmodule CredoSampleModule do
      import Vendor.System, only: [get_env: 1]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "reports a bare call to a function a multi form import brings in" do
    """
    defmodule CredoSampleModule do
      import Vendor.{System}

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Vendor.System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "resolves the base of a multi form import through an alias" do
    """
    defmodule CredoSampleModule do
      alias Vendor, as: Dep
      import Dep.{System}

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Vendor.System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "does not report a bare call to a function an unconfigured multi form import brings in" do
    """
    defmodule CredoSampleModule do
      import Vendor.{System}

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a bare call a Kernel import restricted with only leaves out" do
    """
    defmodule CredoSampleModule do
      import Kernel, only: [def: 2]

      def run(value), do: dbg(value)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> refute_issues()
  end

  test "reports a bare call a Kernel import names in only" do
    """
    defmodule CredoSampleModule do
      import Kernel, only: [def: 2, dbg: 1]

      def run(value), do: dbg(value)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> assert_issue(fn issue -> assert issue.trigger == "dbg" end)
  end

  test "does not report a bare call in a module that a sibling module imports for" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1]

      def run, do: get_env("HOME")
    end

    defmodule CredoSampleModule.Other do
      def get_env(name), do: name

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "reports a bare call an enclosing module imports for" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1]

      defmodule Inner do
        def run, do: get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "reports a bare call a sibling module takes back from Kernel" do
    """
    defmodule CredoSampleModule do
      import Kernel, except: [dbg: 1]

      def dbg(value), do: value

      def run(value), do: dbg(value)
    end

    defmodule CredoSampleModule.Other do
      def run(value), do: dbg(value)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
    |> assert_issue(fn issue -> assert issue.line_no == 10 end)
  end

  test "does not report a bare call outside the function body that imports for it" do
    """
    defmodule CredoSampleModule do
      def run do
        import System, only: [get_env: 1]

        get_env("HOME")
      end

      def get_env(name), do: name

      def other, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "does not report a bare call after the anonymous function that imports for it" do
    """
    defmodule CredoSampleModule do
      def get_env(name), do: name

      def run do
        fn ->
          import System, only: [get_env: 1]

          get_env("HOME")
        end

        get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 8 end)
  end

  test "does not report a bare call in a block beside the one that imports for it" do
    """
    defmodule CredoSampleModule do
      def get_env(name), do: name

      def run do
        try do
          import System, only: [get_env: 1]

          get_env("HOME")
        after
          get_env("HOME")
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 8 end)
  end

  test "does not report a bare call in a clause beside the one that imports for it" do
    """
    defmodule CredoSampleModule do
      def get_env(name), do: name

      def run(value) do
        case value do
          :env ->
            import System, only: [get_env: 1]

            get_env("HOME")

          _other ->
            get_env("HOME")
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 9 end)
  end

  test "does not report a bare call after a block written beside an option" do
    """
    defmodule CredoSampleModule do
      def get_env(name), do: name

      def run(names) do
        for name <- names,
            into: %{},
            do:
              (
                import System, only: [get_env: 1]

                {name, get_env(name)}
              )

        get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.line_no == 11 end)
  end

  test "reports a bare call at an arity a Kernel except does not take back" do
    """
    defmodule CredoSampleModule do
      import Kernel, except: [inspect: 2]

      def run(value), do: inspect(value)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :inspect}])
    |> assert_issue(fn issue -> assert issue.trigger == "inspect" end)
  end

  test "does not report a bare call at an arity an import leaves out" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 2]

      def get_env(name), do: name

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> refute_issues()
  end

  test "does not report a bare call at an arity the imported module does not export" do
    """
    defmodule CredoSampleModule do
      import System

      def run, do: get_env("HOME", "default", :keep)

      defp get_env(name, default, keep), do: {name, default, keep}
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "reports a bare call at an arity the imported module exports as a macro" do
    """
    defmodule CredoSampleModule do
      import Kernel, except: [inspect: 1]

      def run(value), do: to_string(value)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :to_string}])
    |> assert_issue(fn issue -> assert issue.trigger == "to_string" end)
  end

  test "does not report a bare call at an arity Kernel does not export" do
    """
    defmodule CredoSampleModule do
      def run(value, opts, extra), do: to_string(value, opts, extra)

      defp to_string(value, opts, extra), do: {value, opts, extra}
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :to_string}])
    |> refute_issues()
  end

  test "reports a bare call to a special form Kernel is not the module of" do
    """
    defmodule CredoSampleModule do
      def run(port) do
        receive do
          {^port, message} -> message
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :receive}])
    |> assert_issue(fn issue -> assert issue.trigger == "receive" end)
  end

  test "reports a special form at the arity it is written with" do
    """
    defmodule CredoSampleModule do
      def run(list, other) do
        for value <- list, match <- other, do: {value, match}
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :for}])
    |> assert_issue(fn issue -> assert issue.trigger == "for" end)
  end

  test "reports a bare call to a module the check cannot load" do
    """
    defmodule CredoSampleModule do
      import Vendor.System

      def run, do: get_env("HOME", "default", :keep)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Vendor.System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "does not report a bare call a later import of the same module leaves out" do
    """
    defmodule CredoSampleModule do
      import System
      import System, only: [cmd: 2]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> refute_issues()
  end

  test "does not report a bare call a later except filters out of an earlier only" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1, cmd: 2]
      import System, except: [get_env: 1]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> refute_issues()
  end

  test "reports a bare call a later except leaves in an earlier only" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1, cmd: 2]
      import System, except: [cmd: 2]

      def run, do: get_env("HOME")
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [System])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "reports a piped call at the arity the pipe gives it" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1]

      def run(name), do: name |> get_env()
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "reports a piped call written without parentheses" do
    """
    defmodule CredoSampleModule do
      import System, only: [get_env: 1]

      def run(name), do: name |> get_env
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "does not report a piped call at an arity the file takes back from Kernel" do
    """
    defmodule CredoSampleModule do
      import Kernel, except: [inspect: 1]

      def inspect(value), do: value

      def run(value), do: value |> inspect()
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :inspect}])
    |> refute_issues()
  end

  test "reports a forbidden call written inside a pipeline" do
    """
    defmodule CredoSampleModule do
      def run(name), do: name |> String.upcase() |> System.get_env()
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{System, :get_env}])
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "does not report a bare call whose name the file takes back from Kernel" do
    """
    defmodule CredoSampleModule do
      import Kernel, except: [dbg: 1]

      def dbg(value), do: value

      def run(value), do: dbg(value)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{Kernel, :dbg}])
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
      defdelegate dbg(value), to: Acme.Other
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
      hint: "See Acme.Config."
    )
    |> assert_issue(fn issue ->
      assert issue.message == "Use the runtime config instead. See Acme.Config."
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
      alias Acme.System

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
        Acme.Env.get_env("HOME")
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
      use Acme.Worker, retries: System.get_env("RETRIES")
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

  test "resolves a call written through an alias for an Erlang module" do
    """
    defmodule CredoSampleModule do
      alias :rand, as: Random

      def run, do: Random.uniform(3)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{:rand, :uniform}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Random.uniform"
      assert issue.message == "The `:rand.uniform` function must not be called."
    end)
  end

  test "resolves a call through an alias for an Erlang module named on its own" do
    """
    defmodule CredoSampleModule do
      alias :rand, as: Random

      def run, do: Random.bytes(3)
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [:rand])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Random.bytes"
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

  test "raises when a calls entry is neither a module, a pattern, nor a {Module, :function} tuple" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: :ok
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid calls entry 123/, fn ->
      ForbiddenFunctionCall.run(source_file, calls: [123])
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

  test "reports a call to a function on a module a pattern names" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Billing.Domain.NotFoundError.new(%{})
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{"Acme.**.Domain.**Error", :new}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Billing.Domain.NotFoundError.new"

      assert issue.message ==
               "The `Acme.Billing.Domain.NotFoundError.new` function must not be called."
    end)
  end

  test "does not report a call to a function on a module no pattern names" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Billing.Command.NotFoundError.new(%{})
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{"Acme.**.Domain.**Error", :new}])
    |> refute_issues()
  end

  test "does not report a call to another function on a module a pattern names" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Billing.Domain.NotFoundError.message(%{})
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{"Acme.**.Domain.**Error", :new}])
    |> refute_issues()
  end

  test "reports every call to a module a pattern names on its own" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: ["Acme.Legacy.**"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Legacy.Client.fetch"
      assert issue.message == "The `Acme.Legacy.Client.fetch` function must not be called."
    end)
  end

  test "reports a pattern entry with its own message" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: [{"Acme.Legacy.**", "The legacy namespace is being removed."}]
    )
    |> assert_issue(fn issue ->
      assert issue.message == "The legacy namespace is being removed."
    end)
  end

  test "names an Erlang module matched by a pattern as the atom it is written as" do
    """
    defmodule CredoSampleModule do
      def run do
        :os.system_time()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: ["o*"])
    |> assert_issue(fn issue ->
      assert issue.trigger == ":os.system_time"
      assert issue.message == "The `:os.system_time` function must not be called."
    end)
  end

  test "resolves an alias before matching a pattern" do
    """
    defmodule CredoSampleModule do
      alias Acme.Legacy.Client

      def run do
        Client.fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: ["Acme.Legacy.**"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Client.fetch"
    end)
  end

  test "reports a bare call under an import of a module a pattern names" do
    """
    defmodule CredoSampleModule do
      import Acme.Legacy.Client

      def run do
        fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{"Acme.Legacy.**", :fetch}])
    |> assert_issue(fn issue ->
      assert issue.trigger == "fetch"
    end)
  end

  test "does not report a bare call under an import of a module no pattern names" do
    """
    defmodule CredoSampleModule do
      import Acme.Billing.Client

      def run do
        fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: [{"Acme.Legacy.**", :fetch}])
    |> refute_issues()
  end

  test "raises when a pattern matches Kernel as a whole module" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: :ok
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/`Kernel` cannot be forbidden as a whole module/, fn ->
      ForbiddenFunctionCall.run(source_file, calls: ["Kern*"])
    end
  end

  test "does not report a function an except entry names" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: ["Acme.Legacy.**"],
      except: [{Acme.Legacy.Client, :fetch}]
    )
    |> refute_issues()
  end

  test "reports another function on a module an except entry names a function of" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.write()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: ["Acme.Legacy.**"],
      except: [{Acme.Legacy.Client, :fetch}]
    )
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Legacy.Client.write"
    end)
  end

  test "does not report any call to a module an except entry names on its own" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.write()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: ["Acme.Legacy.**"],
      except: [Acme.Legacy.Client]
    )
    |> refute_issues()
  end

  test "does not report a call to a module an except pattern names" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.Http.fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: ["Acme.Legacy.**"],
      except: ["Acme.Legacy.Client.**"]
    )
    |> refute_issues()
  end

  test "does not report a bare call an except entry names" do
    """
    defmodule CredoSampleModule do
      import Acme.Legacy.Client

      def run do
        fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: [{"Acme.Legacy.**", :fetch}],
      except: [{Acme.Legacy.Client, :fetch}]
    )
    |> refute_issues()
  end

  test "does not report a bare call an except entry names through an import list" do
    """
    defmodule CredoSampleModule do
      import Acme.Legacy.Client, only: [fetch: 0]

      def run do
        fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall,
      calls: ["Acme.Legacy.**"],
      except: [{Acme.Legacy.Client, :fetch}]
    )
    |> refute_issues()
  end

  test "is silent when only except is configured" do
    """
    defmodule CredoSampleModule do
      def run do
        System.get_env("HOME")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, except: [{System, :get_env}])
    |> refute_issues()
  end

  test "is silent when except is explicitly set to nil" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Legacy.Client.fetch()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenFunctionCall, calls: ["Acme.Other.**"], except: nil)
    |> refute_issues()
  end

  test "raises when an except entry carries a message" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: :ok
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid except entry/, fn ->
      ForbiddenFunctionCall.run(source_file,
        calls: ["Acme.Legacy.**"],
        except: [{Acme.Legacy.Client, "Allowed for now."}]
      )
    end
  end
end
