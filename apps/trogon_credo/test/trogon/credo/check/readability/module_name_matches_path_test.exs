defmodule Trogon.Credo.Check.Readability.ModuleNameMatchesPathTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.ModuleNameMatchesPath

  test "is inert when root is left as the default nil" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("lib/my_app/wrong_name.ex")
    |> run_check(ModuleNameMatchesPath)
    |> refute_issues()
  end

  test "does not report a module whose path matches its name" do
    """
    defmodule MyApp.Billing.Invoice do
    end
    """
    |> to_source_file("lib/my_app/billing/invoice.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "reports a module whose path does not match its name" do
    """
    defmodule MyApp.Billing.Invoice do
    end
    """
    |> to_source_file("lib/my_app/billing/receipt.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> assert_issue(fn issue ->
      assert issue.message == "The module `MyApp.Billing.Invoice` is expected in `lib/my_app/billing/invoice.ex`."
    end)
  end

  test "underscores a module name ending in a JSON style acronym" do
    """
    defmodule MyApp.ErrorJSON do
    end
    """
    |> to_source_file("lib/my_app/error_json.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "underscores a module name starting with an API style acronym" do
    """
    defmodule MyApp.APIClient do
    end
    """
    |> to_source_file("lib/my_app/api_client.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "compares against the segment below the root in an umbrella style path" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("apps/my_app/lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "does not mistake a directory that only contains root as a match" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("apps/lib_gateway/lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "uses the last segment equal to root when it appears twice" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("lib/legacy/lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "reports against the last segment equal to root when it appears twice" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("lib/legacy/lib/my_app/bar.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> assert_issue(fn issue ->
      assert issue.message == "The module `MyApp.Foo` is expected in `lib/my_app/foo.ex`."
    end)
  end

  test "is silent on a file with no defmodule" do
    """
    if Mix.env() == :test do
      IO.puts("hello")
    end
    """
    |> to_source_file("lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "is silent on a file whose path has no root segment" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("config/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "does not report a nested module" do
    """
    defmodule MyApp.Foo do
      defmodule Nested do
      end
    end
    """
    |> to_source_file("lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "does not treat a defmodule inside a quote block as the file's outermost module" do
    """
    quote do
      defmodule Ghost do
      end
    end

    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "does not report a defmodule whose name is not written as an alias" do
    """
    defmodule :not_an_alias do
    end
    """
    |> to_source_file("lib/my_app/foo.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "checks a root: test instance against a _test.exs file" do
    """
    defmodule MyApp.Billing.InvoiceTest do
    end
    """
    |> to_source_file("test/my_app/billing/invoice_test.exs")
    |> run_check(ModuleNameMatchesPath, root: "test")
    |> refute_issues()
  end

  test "reports a mismatching root: test instance" do
    """
    defmodule MyApp.Billing.InvoiceTest do
    end
    """
    |> to_source_file("test/my_app/billing/receipt_test.exs")
    |> run_check(ModuleNameMatchesPath, root: "test")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `MyApp.Billing.InvoiceTest` is expected in `test/my_app/billing/invoice_test.exs`."
    end)
  end

  test "does not report a module defined at the root itself" do
    """
    defmodule MyApp do
    end
    """
    |> to_source_file("lib/my_app.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> refute_issues()
  end

  test "applies to a defmodule written with an explicit Elixir prefix" do
    """
    defmodule Elixir.MyApp.Foo do
    end
    """
    |> to_source_file("lib/my_app/bar.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> assert_issue(fn issue ->
      assert issue.message == "The module `MyApp.Foo` is expected in `lib/my_app/foo.ex`."
      assert issue.trigger == "Elixir.MyApp.Foo"
    end)
  end

  test "uses the module name as written as the trigger" do
    """
    defmodule MyApp.Billing.Invoice do
    end
    """
    |> to_source_file("lib/my_app/billing/receipt.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib")
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Billing.Invoice" end)
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Billing.Invoice do
    end
    """
    |> to_source_file("lib/my_app/billing/receipt.ex")
    |> run_check(ModuleNameMatchesPath, root: "lib", hint: "Rename the file to invoice.ex.")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `MyApp.Billing.Invoice` is expected in `lib/my_app/billing/invoice.ex`. Rename the file to invoice.ex."
    end)
  end

  test "treats an empty root list the same as nil" do
    """
    defmodule MyApp.Foo do
    end
    """
    |> to_source_file("lib/my_app/wrong_name.ex")
    |> run_check(ModuleNameMatchesPath, root: [])
    |> refute_issues()
  end

  test "raises when root is not a string or an atom" do
    source_file =
      """
      defmodule MyApp.Foo do
      end
      """
      |> to_source_file("lib/my_app/foo.ex")

    assert_raise ArgumentError, ~r/invalid root 123/, fn ->
      ModuleNameMatchesPath.run(source_file, root: 123)
    end
  end
end
