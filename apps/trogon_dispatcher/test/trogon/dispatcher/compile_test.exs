defmodule Trogon.Dispatcher.CompileTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.CircularImportError
  alias Trogon.Dispatcher.DuplicateCommandError
  alias Trogon.Dispatcher.TestSupport, as: Support

  defp compile!(source) do
    Code.compile_string(source)
    :ok
  end

  defp assert_compile_exit(source) do
    Process.flag(:trap_exit, true)
    pid = spawn_link(fn -> compile!(source) end)

    receive do
      {:EXIT, ^pid, {error, _stacktrace}} -> error
      {:EXIT, ^pid, reason} -> flunk("expected a compile failure, got exit: #{inspect(reason)}")
    after
      10_000 -> flunk("expected a compile failure, got none")
    end
  end

  describe "register_command" do
    test "requires :kind" do
      error =
        assert_raise ArgumentError, fn ->
          compile!("""
          defmodule MissingKind do
            use Trogon.Dispatcher
            register_command Trogon.Dispatcher.TestSupport.RegisterUser, []
          end
          """)
        end

      assert Exception.message(error) =~ "Expected: kind: :command or kind: :query"
    end

    test "rejects a kind that is not :command or :query" do
      assert_raise ArgumentError, ~r/Got: :event/, fn ->
        compile!("""
        defmodule EventKind do
          use Trogon.Dispatcher
          register_command Trogon.Dispatcher.TestSupport.RegisterUser, kind: :event
        end
        """)
      end
    end

    test "rejects a command module that is not a struct" do
      assert_raise ArgumentError, ~r/to define a struct/, fn ->
        compile!("""
        defmodule NotAStruct do
          use Trogon.Dispatcher
          register_command Trogon.Dispatcher.TestSupport.Trail, kind: :command
        end
        """)
      end
    end

    test "rejects a handler that does not export handle_command/2" do
      error =
        assert_compile_exit("""
        defmodule MissingHandler do
          use Trogon.Dispatcher
          register_command Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command
        end
        """)

      assert Exception.message(error) =~
               "Missing handler for Trogon.Dispatcher.TestSupport.ArchiveUser in MissingHandler"

      assert Exception.message(error) =~
               "Expected: Trogon.Dispatcher.TestSupport.ArchiveUser to export handle_command/2"
    end
  end

  describe "middleware" do
    test "rejects a module that does not export call/3" do
      assert_raise ArgumentError, ~r/to export call\/3/, fn ->
        compile!("""
        defmodule BadMiddlewareModule do
          use Trogon.Dispatcher
          middleware Trogon.Dispatcher.TestSupport.Trail
          register_command Trogon.Dispatcher.TestSupport.RegisterUser, kind: :command
        end
        """)
      end
    end

    test "dedupes a middleware reached both locally and through an import" do
      registrations = Support.RepeatedMiddlewareDispatcher.__trogon_dispatcher__(:registrations)
      [registration] = registrations

      assert Enum.map(registration.middleware, &elem(&1, 0)) == [Support.Authorize]
    end
  end

  describe "import_dispatcher" do
    test "rejects importing itself" do
      assert_raise CircularImportError, ~r/Circular import/, fn ->
        compile!("""
        defmodule SelfImport do
          use Trogon.Dispatcher
          import_dispatcher SelfImport
        end
        """)
      end
    end

    test "rejects importing a module that is not a dispatcher" do
      assert_raise ArgumentError, ~r/to be a Trogon.Dispatcher/, fn ->
        compile!("""
        defmodule ImportsGarbage do
          use Trogon.Dispatcher
          import_dispatcher Trogon.Dispatcher.TestSupport.Trail
        end
        """)
      end
    end

    test "rejects two registrations of the same command with different handlers" do
      error =
        assert_raise DuplicateCommandError, fn ->
          compile!("""
          defmodule ConflictingHandler do
            use Trogon.Dispatcher
            register_command Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command, to: Trogon.Dispatcher.TestSupport.ArchiveUserHandler
            import_dispatcher Trogon.Dispatcher.TestSupport.AccountsDispatcher
          end
          """)
        end

      assert error.command == Support.ArchiveUser
      assert Exception.message(error) =~ "Conflicting registration for Trogon.Dispatcher.TestSupport.ArchiveUser"
    end

    test "rejects the same command reaching a dispatcher with different middleware chains" do
      assert_raise DuplicateCommandError, ~r/one middleware chain/, fn ->
        compile!("""
        defmodule DivergentLeft do
          use Trogon.Dispatcher
          middleware Trogon.Dispatcher.TestSupport.Authorize
          import_dispatcher Trogon.Dispatcher.TestSupport.BillingDispatcher
        end

        defmodule DivergentRight do
          use Trogon.Dispatcher
          import_dispatcher Trogon.Dispatcher.TestSupport.BillingDispatcher
        end

        defmodule DivergentRoot do
          use Trogon.Dispatcher
          import_dispatcher DivergentLeft
          import_dispatcher DivergentRight
        end
        """)
      end
    end
  end

  describe "use Trogon.Dispatcher" do
    test "rejects a telemetry prefix that is not a non-empty list of atoms" do
      assert_raise ArgumentError, ~r/non-empty list of atoms/, fn ->
        compile!("""
        defmodule BadPrefix do
          use Trogon.Dispatcher, telemetry_prefix: "my_app"
        end
        """)
      end
    end
  end
end
