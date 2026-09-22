defmodule Trogon.Credo.Check.Design.ModuleCardinalityTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Design.ModuleCardinality

  test "is inert when nothing is configured" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality)
    |> refute_issues()
  end

  test "does not report a required pattern a module matches" do
    """
    defmodule Acme.Release do
      def migrate, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: ["Acme.Release"])
    |> refute_issues()
  end

  test "reports a required pattern no module matches" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: ["Acme.Release"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Release"
      assert issue.line_no == 1
      assert issue.message == "No module matches `Acme.Release`, which this project requires."
    end)
  end

  test "reports a required pattern given as a module name" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: [Acme.Release])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Release"
    end)
  end

  test "reports a required pattern given on its own rather than in a list" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: "Acme.Release")
    |> assert_issue()
  end

  test "reports a required pattern with its own message" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality,
      required: [{"Acme.Release", "The release calls `Acme.Release.migrate/0`."}]
    )
    |> assert_issue(fn issue ->
      assert issue.message == "The release calls `Acme.Release.migrate/0`."
    end)
  end

  test "reports a required pattern once, in the first file by name" do
    [
      """
      defmodule Acme.Worker do
        def run, do: :ok
      end
      """
      |> to_source_file("lib/acme/worker.ex"),
      """
      defmodule Acme.Account do
        defstruct [:id]
      end
      """
      |> to_source_file("lib/acme/account.ex")
    ]
    |> run_check(ModuleCardinality, required: ["Acme.Release"])
    |> assert_issue(fn issue ->
      assert issue.filename == "lib/acme/account.ex"
    end)
  end

  test "counts a module defined in any of the analyzed files" do
    [
      """
      defmodule Acme.Worker do
        def run, do: :ok
      end
      """
      |> to_source_file("lib/acme/worker.ex"),
      """
      defmodule Acme.Release do
        def migrate, do: :ok
      end
      """
      |> to_source_file("lib/acme/release.ex")
    ]
    |> run_check(ModuleCardinality, required: ["Acme.Release"])
    |> refute_issues()
  end

  test "counts a nested module under the module that encloses it" do
    """
    defmodule Acme do
      defmodule Release do
        def migrate, do: :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: ["Acme.Release"])
    |> refute_issues()
  end

  test "does not count a module defined inside a quote block" do
    """
    defmodule Acme.Worker do
      defmacro __using__(_opts) do
        quote do
          defmodule Acme.Release do
            def migrate, do: :ok
          end
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: ["Acme.Release"])
    |> assert_issue()
  end

  test "does not count a module whose name is not written as an alias, nor one nested inside it" do
    """
    defmodule __MODULE__.Release do
      defmodule Inner do
        def migrate, do: :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: ["**"])
    |> assert_issue()
  end

  test "does not report a unique pattern only one module matches" do
    """
    defmodule Acme.Billing.HttpClient do
      def get(_url), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, unique: ["Acme.**.HttpClient"])
    |> refute_issues()
  end

  test "reports the module that matches a unique pattern after the first" do
    """
    defmodule Acme.Billing.HttpClient do
      def get(_url), do: :ok
    end

    defmodule Acme.Shipping.HttpClient do
      def get(_url), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, unique: ["Acme.**.HttpClient"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Shipping.HttpClient"
      assert issue.line_no == 5

      assert issue.message ==
               "Only one module may match `Acme.**.HttpClient`, which `Acme.Billing.HttpClient` already does."
    end)
  end

  test "reports every module that matches a unique pattern after the first" do
    """
    defmodule Acme.Billing.HttpClient do
      def get(_url), do: :ok
    end

    defmodule Acme.Shipping.HttpClient do
      def get(_url), do: :ok
    end

    defmodule Acme.Catalog.HttpClient do
      def get(_url), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, unique: ["Acme.**.HttpClient"])
    |> assert_issues(fn issues ->
      assert issues |> Enum.map(& &1.trigger) |> Enum.sort() == [
               "Acme.Catalog.HttpClient",
               "Acme.Shipping.HttpClient"
             ]
    end)
  end

  test "reports a unique pattern with its own message" do
    """
    defmodule Acme.Billing.HttpClient do
      def get(_url), do: :ok
    end

    defmodule Acme.Shipping.HttpClient do
      def get(_url), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality,
      unique: [{"Acme.**.HttpClient", "The HTTP client is configured in one place."}]
    )
    |> assert_issue(fn issue ->
      assert issue.message == "The HTTP client is configured in one place."
    end)
  end

  test "reports a unique match in the later file by name" do
    [
      """
      defmodule Acme.Shipping.HttpClient do
        def get(_url), do: :ok
      end
      """
      |> to_source_file("lib/acme/shipping/http_client.ex"),
      """
      defmodule Acme.Billing.HttpClient do
        def get(_url), do: :ok
      end
      """
      |> to_source_file("lib/acme/billing/http_client.ex")
    ]
    |> run_check(ModuleCardinality, unique: ["Acme.**.HttpClient"])
    |> assert_issue(fn issue ->
      assert issue.filename == "lib/acme/shipping/http_client.ex"
    end)
  end

  test "reads required and unique together as exactly one" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality,
      required: ["Acme.**.HttpClient"],
      unique: ["Acme.**.HttpClient"]
    )
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.**.HttpClient"
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality,
      required: ["Acme.Release"],
      hint: "Copy the module from the project template."
    )
    |> assert_issue(fn issue ->
      assert issue.message ==
               "No module matches `Acme.Release`, which this project requires. Copy the module from the project template."
    end)
  end

  test "accepts required and unique set to nil" do
    """
    defmodule Acme.Worker do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleCardinality, required: nil, unique: nil)
    |> refute_issues()
  end

  test "raises when a required entry is neither a pattern nor a module name" do
    assert_raise ArgumentError, ~r/invalid required entry 123/, fn ->
      run_on_source_file(required: [123])
    end
  end

  test "raises when a unique entry is neither a pattern nor a module name" do
    assert_raise ArgumentError, ~r/invalid unique entry 123/, fn ->
      run_on_source_file(unique: [123])
    end
  end

  test "raises when a {pattern, message} entry's message is not a string" do
    assert_raise ArgumentError, ~r/invalid required entry/, fn ->
      run_on_source_file(required: [{"Acme.Release", :not_a_string}])
    end
  end

  defp run_on_source_file(params) do
    source_file =
      """
      defmodule Acme.Worker do
        def run, do: :ok
      end
      """
      |> to_source_file()

    ModuleCardinality.run_on_all_source_files(Credo.Execution.build(), [source_file], params)
  end
end
