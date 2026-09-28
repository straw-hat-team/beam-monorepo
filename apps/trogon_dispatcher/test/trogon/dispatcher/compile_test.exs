defmodule Trogon.Dispatcher.CompileTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.CircularImportError
  alias Trogon.Dispatcher.DuplicateMessageError
  alias Trogon.Dispatcher.TestSupport, as: Support

  defp compile!(source) do
    Code.compile_string(source)
    :ok
  end

  defp compile_diagnostics(source) do
    previous = Code.get_compiler_option(:infer_signatures)
    Code.put_compiler_option(:infer_signatures, true)

    try do
      {_result, diagnostics} = Code.with_diagnostics(fn -> compile!(source) end)
      diagnostics
    after
      Code.put_compiler_option(:infer_signatures, previous)
    end
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

  describe "register_message" do
    test "requires :kind" do
      error =
        assert_raise ArgumentError, fn ->
          compile!("""
          defmodule MissingKind do
            use Trogon.Dispatcher
            register_message Trogon.Dispatcher.TestSupport.RegisterUser, []
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
          register_message Trogon.Dispatcher.TestSupport.RegisterUser, kind: :event
        end
        """)
      end
    end

    test "rejects a message module that is not a struct" do
      assert_raise ArgumentError, ~r/to define a struct/, fn ->
        compile!("""
        defmodule NotAStruct do
          use Trogon.Dispatcher
          register_message Trogon.Dispatcher.TestSupport.Trail, kind: :command
        end
        """)
      end
    end

    test "rejects a handler that does not export handle_message/2" do
      error =
        assert_compile_exit("""
        defmodule MissingHandler do
          use Trogon.Dispatcher
          register_message Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command
        end
        """)

      assert Exception.message(error) =~
               "Missing handler for Trogon.Dispatcher.TestSupport.ArchiveUser in MissingHandler"

      assert Exception.message(error) =~
               "Expected: Trogon.Dispatcher.TestSupport.ArchiveUser to export handle_message/2"
    end

    test "rejects two local registrations of the same message with different handlers" do
      error =
        assert_raise DuplicateMessageError, fn ->
          compile!("""
          defmodule ConflictingHandlerOnly do
            use Trogon.Dispatcher
            register_message Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command, to: Trogon.Dispatcher.TestSupport.ArchiveUserHandler
            register_message Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command, to: Trogon.Dispatcher.TestSupport.RegisterUser
          end
          """)
        end

      assert error.dispatched_message == Support.ArchiveUser
      assert Exception.message(error) =~ "Conflicting registration for Trogon.Dispatcher.TestSupport.ArchiveUser"
      assert Exception.message(error) =~ "handler: Trogon.Dispatcher.TestSupport.ArchiveUserHandler"
      assert Exception.message(error) =~ "handler: Trogon.Dispatcher.TestSupport.RegisterUser"
    end

    test "rejects two local registrations of the same message with different kinds" do
      error =
        assert_raise DuplicateMessageError, fn ->
          compile!("""
          defmodule ConflictingKindOnly do
            use Trogon.Dispatcher
            register_message Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command, to: Trogon.Dispatcher.TestSupport.ArchiveUserHandler
            register_message Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :query, to: Trogon.Dispatcher.TestSupport.ArchiveUserHandler
          end
          """)
        end

      assert error.dispatched_message == Support.ArchiveUser
      assert Exception.message(error) =~ "Conflicting registration for Trogon.Dispatcher.TestSupport.ArchiveUser"
      assert Exception.message(error) =~ "kind: :command"
      assert Exception.message(error) =~ "kind: :query"
    end

    @tag :type_checker
    test "warns at the registration and at each import when the handler cannot accept the message" do
      diagnostics =
        compile_diagnostics("""
        defmodule OnlyArchivesUsers do
          def handle_message(%Trogon.Dispatcher.TestSupport.ArchiveUser{}, _context), do: :ok
        end

        defmodule MismatchedHandler do
          use Trogon.Dispatcher
          register_message Trogon.Dispatcher.TestSupport.RegisterUser, kind: :command, to: OnlyArchivesUsers
        end

        defmodule ImportsMismatchedHandler do
          use Trogon.Dispatcher
          import_dispatcher MismatchedHandler
        end
        """)

      assert diagnostics |> Enum.map(& &1.position) |> Enum.sort() == [7, 12]

      for diagnostic <- diagnostics do
        assert diagnostic.severity == :warning
        assert diagnostic.message =~ "incompatible types given to OnlyArchivesUsers.handle_message/2"
      end
    end

    @tag :type_checker
    test "does not warn when the handler accepts the message" do
      diagnostics =
        compile_diagnostics("""
        defmodule HandlesBothUserMessages do
          def handle_message(%Trogon.Dispatcher.TestSupport.RegisterUser{}, _context), do: :ok
          def handle_message(%Trogon.Dispatcher.TestSupport.ArchiveUser{}, _context), do: :ok
        end

        defmodule MatchingHandler do
          use Trogon.Dispatcher
          register_message Trogon.Dispatcher.TestSupport.RegisterUser, kind: :command, to: HandlesBothUserMessages
          register_message Trogon.Dispatcher.TestSupport.ArchiveUser, kind: :command, to: HandlesBothUserMessages
        end
        """)

      assert diagnostics == []
    end
  end

  describe "middleware" do
    test "rejects a module that does not export call/3" do
      assert_raise ArgumentError, ~r/to export call\/3/, fn ->
        compile!("""
        defmodule BadMiddlewareModule do
          use Trogon.Dispatcher
          middleware Trogon.Dispatcher.TestSupport.Trail
          register_message Trogon.Dispatcher.TestSupport.RegisterUser, kind: :command
        end
        """)
      end
    end

    test "rejects a middleware whose init/1 does not return a struct" do
      assert_raise ArgumentError, ~r/to return a struct/, fn ->
        compile!("""
        defmodule NonStructInitDispatcher do
          use Trogon.Dispatcher
          middleware Trogon.Dispatcher.TestSupport.NonStructInit
          register_message Trogon.Dispatcher.TestSupport.RegisterUser, kind: :command
        end
        """)
      end
    end

    test "runs a middleware reached both locally and through an import at each layer" do
      compile!("""
      defmodule SharedLeafDispatcher do
        use Trogon.Dispatcher
        middleware Trogon.Dispatcher.TestSupport.NoInit, layer: :leaf
        register_message Trogon.Dispatcher.TestSupport.BillingCommand, kind: :command
      end

      defmodule SharedRootDispatcher do
        use Trogon.Dispatcher
        middleware Trogon.Dispatcher.TestSupport.NoInit, layer: :leaf
        import_dispatcher SharedLeafDispatcher
      end
      """)

      assert {:ok, %{trail: [{:no_init, [layer: :leaf]}, {:no_init, [layer: :leaf]}]}} =
               SharedRootDispatcher.dispatch_message(%Support.BillingCommand{})
    end

    test "runs a middleware listed twice with identical options twice, in declaration order" do
      compile!("""
      defmodule DoubleListedMiddlewareDispatcher do
        use Trogon.Dispatcher
        middleware Trogon.Dispatcher.TestSupport.NoInit, step: :first
        middleware Trogon.Dispatcher.TestSupport.NoInit, step: :first
        middleware Trogon.Dispatcher.TestSupport.NoInit, step: :last
        register_message Trogon.Dispatcher.TestSupport.BillingCommand, kind: :command
      end
      """)

      assert {:ok, %{trail: [{:no_init, [step: :first]}, {:no_init, [step: :first]}, {:no_init, [step: :last]}]}} =
               DoubleListedMiddlewareDispatcher.dispatch_message(%Support.BillingCommand{})
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

    @tag :tmp_dir
    test "rejects a cross-file cycle that the parallel compiler cannot resolve", %{tmp_dir: tmp_dir} do
      unique = System.unique_integer([:positive])
      mod_a_name = "CycA#{unique}"
      mod_b_name = "CycB#{unique}"
      mod_a = :"Elixir.#{mod_a_name}"
      mod_b = :"Elixir.#{mod_b_name}"

      on_exit(fn ->
        :code.purge(mod_a)
        :code.delete(mod_a)
        :code.purge(mod_b)
        :code.delete(mod_b)
      end)

      path_a = Path.join(tmp_dir, "cyc_a.ex")
      path_b = Path.join(tmp_dir, "cyc_b.ex")

      File.write!(path_a, """
      defmodule #{mod_a_name} do
        use Trogon.Dispatcher
        import_dispatcher #{mod_b_name}
      end
      """)

      File.write!(path_b, """
      defmodule #{mod_b_name} do
        use Trogon.Dispatcher
        import_dispatcher #{mod_a_name}
      end
      """)

      {:error, diagnostics, _warnings} =
        Kernel.ParallelCompiler.compile([path_a, path_b], return_diagnostics: true)

      assert Enum.any?(diagnostics, &(&1.message =~ "Circular import"))
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

    test "rejects two dispatchers registering the same message even when their pipelines match" do
      error =
        assert_raise DuplicateMessageError, ~r/one registering dispatcher/, fn ->
          compile!("""
          defmodule OwnerLeft do
            use Trogon.Dispatcher
            register_message Trogon.Dispatcher.TestSupport.BillingCommand, kind: :command
          end

          defmodule OwnerRight do
            use Trogon.Dispatcher
            register_message Trogon.Dispatcher.TestSupport.BillingCommand, kind: :command
          end

          defmodule TwoOwners do
            use Trogon.Dispatcher
            import_dispatcher OwnerLeft
            import_dispatcher OwnerRight
          end
          """)
        end

      assert error.existing.registered_by == OwnerLeft
      assert error.conflicting.registered_by == OwnerRight
    end

    test "rejects the same message reaching a dispatcher with different middleware chains" do
      assert_raise DuplicateMessageError, ~r/one middleware chain/, fn ->
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
    test "rejects options" do
      assert_raise ArgumentError, ~r/takes no options/, fn ->
        compile!("""
        defmodule WithOptions do
          use Trogon.Dispatcher, telemetry_prefix: [:my_app]
        end
        """)
      end
    end
  end
end
