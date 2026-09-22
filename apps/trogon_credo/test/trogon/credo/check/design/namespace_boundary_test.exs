defmodule Trogon.Credo.Check.Design.NamespaceBoundaryTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Design.NamespaceBoundary

  test "is inert when forbidden is left as the default empty list" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary)
    |> refute_issues()
  end

  test "is inert when forbidden is explicitly set to nil" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: nil)
    |> refute_issues()
  end

  test "does not report code that never references a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run, do: Enum.map([1, 2, 3], & &1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> refute_issues()
  end

  test "reports a qualified call to a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Repo"
      assert issue.message == "A module in this namespace must not reference `MyApp.Repo`."
    end)
  end

  test "reports a struct literal referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run, do: %MyApp.Repo.Account{}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo.Account" end)
  end

  test "reports a struct pattern in a function head referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run(%MyApp.Repo.Account{id: id}), do: id
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo.Account" end)
  end

  test "reports an import target referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      import MyApp.Repo
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "reports a require target referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      require MyApp.Repo
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "reports a use target referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      use MyApp.Repo
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "reports a module named as a plain value inside a tuple" do
    """
    defmodule CredoSampleModule do
      def run, do: {:ok, MyApp.Repo}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "reports a module named as a plain value inside a function capture" do
    """
    defmodule CredoSampleModule do
      def run, do: Enum.map([1], &MyApp.Repo.load/1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "does not report the name in a defmodule head" do
    """
    defmodule MyApp.Processor.Sync do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Processor.**"])
    |> refute_issues()
  end

  test "does not report a defmodule head at any nesting depth" do
    """
    defmodule MyApp.Outer do
      defmodule MyApp.Outer.Inner do
        def run, do: :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**"])
    |> refute_issues()
  end

  test "an except pattern suppresses a match" do
    """
    defmodule MyApp.Billing.Domain.Invoice do
      def run, do: MyApp.Billing.Domain.Invoice.Line.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      forbidden: ["MyApp.**"],
      except: ["MyApp.**.Domain.**", "MyApp.Billing.Domain.**"]
    )
    |> refute_issues()
  end

  test "an except pattern only suppresses the reference it matches" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Domain.Invoice.new()
        MyApp.Repo.get(1)
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**"], except: ["MyApp.Domain.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "a single segment wildcard does not cross a dot" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Billing.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.*.Domain"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Billing.Domain" end)
  end

  test "a single segment wildcard staying silent once the reference crosses a dot" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Billing.Extra.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.*.Domain"])
    |> refute_issues()
  end

  test "a double wildcard crosses segments" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Billing.Extra.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**.Domain"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Billing.Extra.Domain" end)
  end

  test "a double wildcard on each side of a segment requires at least one segment on each side" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Domain.Invoice.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**.Domain.**"])
    |> refute_issues()
  end

  test "a double wildcard on each side of a segment matches once both sides are present" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Billing.Domain.Invoice.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**.Domain.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Billing.Domain.Invoice" end)
  end

  test "a suffix pattern matches a module under the namespace whose name ends in the suffix" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Billing.NotFoundError.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**Error"])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Billing.NotFoundError" end)
  end

  test "a suffix pattern does not match the namespace root itself" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Error.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**Error"])
    |> refute_issues()
  end

  test "an exact pattern without a wildcard does not match a nested module" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.Account.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> refute_issues()
  end

  test "a trailing double wildcard does not match the namespace root itself" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo.**"])
    |> refute_issues()
  end

  test "a bare alias stays silent while a call written through it is reported" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Repo

      def run, do: Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo"
      assert issue.message == "A module in this namespace must not reference `MyApp.Repo`."
    end)
  end

  test "an unused alias to a forbidden module is not reported" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Repo

      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> refute_issues()
  end

  test "a renamed alias stays silent" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Repo, as: DataStore

      def run, do: DataStore.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "DataStore" end)
  end

  test "a multi form directive is not resolved into its individual members" do
    """
    defmodule CredoSampleModule do
      import MyApp.Repo.{Account, Billing}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo.**"])
    |> refute_issues()
  end

  test "a module named inside a typespec is not reported" do
    """
    defmodule CredoSampleModule do
      @type account :: MyApp.Repo.Account.t()

      @spec run(MyApp.Repo.Account.t()) :: :ok
      def run(_account), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo.**"])
    |> refute_issues()
  end

  test "code inside a quote block is not analyzed" do
    """
    defmodule MyApp.Macros do
      defmacro build do
        quote do
          MyApp.Repo.get(1)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> refute_issues()
  end

  test "uses a custom message from a {pattern, message} entry" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: [{"MyApp.Repo", "Use the domain context instead of the repository."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Use the domain context instead of the repository."
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"], hint: "Call MyApp.Accounts instead.")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "A module in this namespace must not reference `MyApp.Repo`. Call MyApp.Accounts instead."
    end)
  end

  test "treats a regex metacharacter inside a pattern as a literal character" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Foo.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Foo?"])
    |> refute_issues()
  end

  test "does not report a reference to an Erlang module written as a plain atom" do
    """
    defmodule CredoSampleModule do
      def run, do: :os.system_time()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.**"])
    |> refute_issues()
  end

  test "does not report an ambiguous name as the module it is written as" do
    """
    defmodule A do
      alias Vendor.Client

      def run, do: Client.call()
    end

    defmodule B do
      alias MyApp.Client

      def run, do: Client.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Client"])
    |> refute_issues()
  end

  test "reports a module written with an explicit Elixir prefix" do
    """
    defmodule CredoSampleModule do
      def run, do: Elixir.MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Repo"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.MyApp.Repo"
      assert issue.message == "A module in this namespace must not reference `MyApp.Repo`."
    end)
  end

  test "accepts a plain module name given as an atom" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: [MyApp.Repo])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo" end)
  end

  test "raises when a forbidden pattern is not a binary or a module name" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid namespace boundary pattern 123/, fn ->
      NamespaceBoundary.run(source_file, forbidden: [123])
    end
  end

  test "raises when a {pattern, message} entry's message is not a string" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid forbidden entry/, fn ->
      NamespaceBoundary.run(source_file, forbidden: [{"MyApp.Repo", :not_a_string}])
    end
  end

  test "raises when an except entry carries a message" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid namespace boundary pattern/, fn ->
      NamespaceBoundary.run(source_file,
        forbidden: ["MyApp.**"],
        except: [{"MyApp.Repo", "The repo is fine here."}]
      )
    end
  end

  test "raises when an except pattern is not a binary or a module name" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid namespace boundary pattern/, fn ->
      NamespaceBoundary.run(source_file, forbidden: ["MyApp.**"], except: [123])
    end
  end
end
