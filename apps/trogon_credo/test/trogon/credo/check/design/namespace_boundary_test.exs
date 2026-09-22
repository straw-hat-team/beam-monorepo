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

  test "is inert when private_to is left as the default empty list" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary)
    |> refute_issues()
  end

  test "is inert when private_to is explicitly set to nil" do
    """
    defmodule CredoSampleModule do
      def run, do: MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: nil)
    |> refute_issues()
  end

  test "does not report a private module referenced from inside its owning namespace" do
    """
    defmodule MyApp.BillingService.CreateInvoice do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> refute_issues()
  end

  test "reports a private module referenced from outside its owning namespace" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.BillingService.NotFoundError"

      assert issue.message ==
               "The module `MyApp.BillingService.NotFoundError` is private to `MyApp.BillingService`."
    end)
  end

  test "reports a private module referenced from a sibling namespace matching the same pattern" do
    """
    defmodule MyApp.ShippingService.CreateLabel do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `MyApp.BillingService.NotFoundError` is private to `MyApp.BillingService`."
    end)
  end

  test "does not report a module that matches the owning prefix but not the private part" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run, do: MyApp.BillingService.Handler.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> refute_issues()
  end

  test "a pattern that is only the owning prefix makes a namespace private to itself" do
    """
    defmodule MyApp.Processor.Shipping do
      def run, do: MyApp.Processor.Billing.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.Processor.*)"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `MyApp.Processor.Billing` is private to `MyApp.Processor.Billing`."
    end)
  end

  test "a namespace private to itself may still reference what is under it" do
    """
    defmodule MyApp.Processor.Shipping do
      def run, do: MyApp.Processor.Shipping.Step.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.Processor.*)"])
    |> refute_issues()
  end

  test "binds the owning namespace to the longest match a pattern allows" do
    """
    defmodule MyApp.Service.Billing.V1.OtherService.Handler do
      def run, do: raise MyApp.Service.Billing.V1.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.**.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `MyApp.Service.Billing.V1.BillingService.NotFoundError` is private to `MyApp.Service.Billing.V1.BillingService`."
    end)
  end

  test "does not report the head of the private module's own definition" do
    """
    defmodule MyApp.BillingService.NotFoundError do
      defexception message: "not found"
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> refute_issues()
  end

  test "resolves an alias before deciding whether a reference crosses a privacy boundary" do
    """
    defmodule MyApp.Web.InvoiceController do
      alias MyApp.BillingService.NotFoundError

      def run, do: raise NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "NotFoundError"

      assert issue.message ==
               "The module `MyApp.BillingService.NotFoundError` is private to `MyApp.BillingService`."
    end)
  end

  test "accepts a single private_to pattern given on its own" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: "(MyApp.*Service).**Error")
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.BillingService.NotFoundError"
    end)
  end

  test "reports a private_to entry with its own message" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: [{"(MyApp.*Service).**Error", "Return the service's public error instead."}]
    )
    |> assert_issue(fn issue ->
      assert issue.message == "Return the service's public error instead."
    end)
  end

  test "appends the hint to a privacy issue" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: ["(MyApp.*Service).**Error"],
      hint: "See the service boundaries guide."
    )
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `MyApp.BillingService.NotFoundError` is private to `MyApp.BillingService`. See the service boundaries guide."
    end)
  end

  test "carves an exception out of private_to with except" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: ["(MyApp.*Service).**Error"],
      except: ["MyApp.BillingService.NotFoundError"]
    )
    |> refute_issues()
  end

  test "does not report a privacy violation in a file that defines no module" do
    """
    raise MyApp.BillingService.NotFoundError
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> refute_issues()
  end

  test "does not report a privacy violation in a file whose outermost module is not an alias" do
    """
    defmodule Module.concat(MyApp, Web) do
      def run, do: raise MyApp.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> refute_issues()
  end

  test "does not report a reference written inside a quote block" do
    """
    defmodule MyApp.Web.InvoiceController do
      defmacro guard do
        quote do
          raise MyApp.BillingService.NotFoundError
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(MyApp.*Service).**Error"])
    |> refute_issues()
  end

  test "raises when forbidden and private_to are set together" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid configuration/, fn ->
      NamespaceBoundary.run(source_file,
        forbidden: ["MyApp.Repo"],
        private_to: ["(MyApp.*Service).**Error"]
      )
    end
  end

  test "raises when a private_to pattern names no owning namespace" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to pattern/, fn ->
      NamespaceBoundary.run(source_file, private_to: ["MyApp.*Service.**Error"])
    end
  end

  test "raises when a private_to pattern has something other than a namespace after the prefix" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to pattern/, fn ->
      NamespaceBoundary.run(source_file, private_to: ["(MyApp.*Service)Error"])
    end
  end

  test "raises when a private_to pattern is not a binary" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to pattern/, fn ->
      NamespaceBoundary.run(source_file, private_to: [MyApp.BillingService])
    end
  end

  test "raises when a private_to entry carries a message that is not a string" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to entry/, fn ->
      NamespaceBoundary.run(source_file, private_to: [{"(MyApp.*Service).**Error", :nope}])
    end
  end

  test "reports a reference written in a pattern by default" do
    """
    defmodule CredoSampleModule do
      def run(%MyApp.Domain.NotFoundError{}), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Domain.NotFoundError"
    end)
  end

  test "does not report a struct matched in a clause head when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(result) do
        case result do
          {:error, %MyApp.Domain.NotFoundError{}} -> :missing
          other -> other
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a struct matched in a function head when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(%MyApp.Domain.NotFoundError{} = error) when is_struct(error), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a pattern on the left of a match or a generator when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(result) do
        %MyApp.Domain.NotFoundError{} = result

        with %MyApp.Domain.ConflictError{} <- result do
          :ok
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a rescue clause when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run do
        :ok
      rescue
        MyApp.Domain.NotFoundError -> :missing
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "reports a struct built in expression position when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run, do: {:error, %MyApp.Domain.NotFoundError{}}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Domain.NotFoundError"
    end)
  end

  test "reports a raised module when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run, do: raise MyApp.Domain.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Domain.NotFoundError"
    end)
  end

  test "reports the value side of a match and of a generator when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run do
        error = %MyApp.Domain.NotFoundError{}

        with :ok <- MyApp.Domain.Guard.call() do
          error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "reports a cond condition when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        cond do
          MyApp.Domain.Guard.call(value) -> :ok
          true -> :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Domain.Guard"
    end)
  end

  test "does not report a struct built as a default argument value when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(error \\\\ %MyApp.Domain.NotFoundError{}), do: error
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["MyApp.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "narrows private_to to expression position as well when in_patterns is false" do
    """
    defmodule MyApp.Web.InvoiceController do
      def run(result) do
        case result do
          {:error, %MyApp.BillingService.NotFoundError{}} -> :missing
          other -> other
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: ["(MyApp.*Service).**Error"],
      in_patterns: false
    )
    |> refute_issues()
  end

  test "raises when in_patterns is not a boolean" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: MyApp.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid in_patterns/, fn ->
      NamespaceBoundary.run(source_file, forbidden: ["MyApp.Repo"], in_patterns: :nope)
    end
  end
end
