defmodule Mix.Tasks.Trogon.TypeProvider.ListTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trogon.TypeProvider.List, as: ListTask

  test "lists type mappings for a valid TypeProvider" do
    output =
      capture_io(fn ->
        ListTask.run(["Trogon.TypeProvider.TestSupport.AccountTypeProvider"])
      end)

    expected_output = """
    Type mappings for Trogon.TypeProvider.TestSupport.AccountTypeProvider:
    Type Name                            | Struct Module
    -------------------------------------+-----------------------------------------------------------------
    something_with_enforce_keys_happened | Trogon.TypeProvider.TestSupport.SomethingWithEnforceKeysHappened
    account_created                      | Trogon.TypeProvider.TestSupport.AccountCreated

    Total: 2 type mappings
    """

    assert output == expected_output
  end

  test "lists type mappings with prefix for a TypeProvider with prefix" do
    output =
      capture_io(fn ->
        ListTask.run(["Trogon.TypeProvider.TestSupport.AccountWithPrefixTypeProvider"])
      end)

    expected_output = """
    Type mappings for Trogon.TypeProvider.TestSupport.AccountWithPrefixTypeProvider:
    Type Name                | Struct Module
    -------------------------+-----------------------------------------------
    accounts.account_locked  | Trogon.TypeProvider.TestSupport.AccountLocked
    accounts.account_created | Trogon.TypeProvider.TestSupport.AccountCreated

    Total: 2 type mappings
    """

    assert output == expected_output
  end

  test "shows error when no arguments provided" do
    error_output =
      capture_io(:stderr, fn ->
        info_output =
          capture_io(fn ->
            ListTask.run([])
          end)

        send(self(), {:info_output, info_output})
      end)

    receive do
      {:info_output, info_output} ->
        assert strip_ansi(error_output) == "No TypeProvider module specified.\n"
        assert info_output == "\nUsage: mix trogon.type_provider.list MyApp.TypeProvider\n"
    end
  end

  test "shows error when too many arguments provided" do
    output =
      capture_io(:stderr, fn ->
        ListTask.run(["Module1", "Module2"])
      end)

    assert strip_ansi(output) == "Too many arguments. Expected one module name.\n"
  end

  test "shows error when module does not exist" do
    output =
      capture_io(:stderr, fn ->
        ListTask.run(["NonExistentModule"])
      end)

    assert strip_ansi(output) == "Module NonExistentModule is not a TypeProvider or not compiled\n"
  end

  test "shows error when module is not a TypeProvider" do
    output =
      capture_io(:stderr, fn ->
        ListTask.run(["String"])
      end)

    assert strip_ansi(output) == "Module String is not a TypeProvider or not compiled\n"
  end

  test "handles empty TypeProvider correctly" do
    output =
      capture_io(fn ->
        ListTask.run(["Trogon.TypeProvider.TestSupport.EmptyTypeProvider"])
      end)

    assert output == "No type mappings found in Trogon.TypeProvider.TestSupport.EmptyTypeProvider\n"
  end

  test "works with fully qualified Elixir module names" do
    output =
      capture_io(fn ->
        ListTask.run(["Elixir.Trogon.TypeProvider.TestSupport.SingleMappingTypeProvider"])
      end)

    expected_output = """
    Type mappings for Elixir.Trogon.TypeProvider.TestSupport.SingleMappingTypeProvider:
    Type Name  | Struct Module
    -----------+------------------------------------------
    test_event | Trogon.TypeProvider.TestSupport.TestEvent

    Total: 1 type mappings
    """

    assert output == expected_output
  end

  test "handles unexpected errors during module operations" do
    Code.compile_quoted(
      quote do
        defmodule BrokenTypeProvider do
          use Trogon.TypeProvider

          def __type_mapping__ do
            raise RuntimeError, "Something went wrong"
          end
        end
      end
    )

    output =
      capture_io(:stderr, fn ->
        ListTask.run(["BrokenTypeProvider"])
      end)

    assert strip_ansi(output) == "Error loading module BrokenTypeProvider: Something went wrong\n"
  end

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end
