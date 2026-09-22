defmodule Trogon.Credo.Check.Design.NamespaceBoundaryTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Design.NamespaceBoundary

  test "is inert when forbidden is left as the default empty list" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary)
    |> refute_issues()
  end

  test "is inert when forbidden is explicitly set to nil" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.get(1)
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
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> refute_issues()
  end

  test "reports a qualified call to a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Repo"
      assert issue.message == "A module in this namespace must not reference `Acme.Repo`."
    end)
  end

  test "reports a struct literal referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run, do: %Acme.Repo.Account{}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo.Account" end)
  end

  test "reports a struct pattern in a function head referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run(%Acme.Repo.Account{id: id}), do: id
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo.Account" end)
  end

  test "reports an import target referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      import Acme.Repo
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "reports a require target referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      require Acme.Repo
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "reports a use target referencing a forbidden module" do
    """
    defmodule CredoSampleModule do
      use Acme.Repo
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "reports a module named as a plain value inside a tuple" do
    """
    defmodule CredoSampleModule do
      def run, do: {:ok, Acme.Repo}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "reports a module named as a plain value inside a function capture" do
    """
    defmodule CredoSampleModule do
      def run, do: Enum.map([1], &Acme.Repo.load/1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "does not report the name in a defmodule head" do
    """
    defmodule Acme.Processor.Sync do
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Processor.**"])
    |> refute_issues()
  end

  test "does not report a defmodule head at any nesting depth" do
    """
    defmodule Acme.Outer do
      defmodule Acme.Outer.Inner do
        def run, do: :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**"])
    |> refute_issues()
  end

  test "an except pattern suppresses a match" do
    """
    defmodule Acme.Billing.Domain.Invoice do
      def run, do: Acme.Billing.Domain.Invoice.Line.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      forbidden: ["Acme.**"],
      except: ["Acme.**.Domain.**", "Acme.Billing.Domain.**"]
    )
    |> refute_issues()
  end

  test "an except pattern only suppresses the reference it matches" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Domain.Invoice.new()
        Acme.Repo.get(1)
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**"], except: ["Acme.Domain.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "a single segment wildcard does not cross a dot" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Billing.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.*.Domain"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Domain" end)
  end

  test "a single segment wildcard staying silent once the reference crosses a dot" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Billing.Extra.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.*.Domain"])
    |> refute_issues()
  end

  test "a double wildcard crosses segments" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Billing.Extra.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**.Domain"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Extra.Domain" end)
  end

  test "a middle double wildcard matches a name with nothing in its place" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Domain.Invoice.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**.Domain.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Domain.Invoice" end)
  end

  test "a leading double wildcard matches a name with nothing in its place" do
    """
    defmodule CredoSampleModule do
      def run, do: Domain.Invoice.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["**.Domain.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "Domain.Invoice" end)
  end

  test "a middle double wildcard matches a name with nothing in its place before a literal segment" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Domain.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**.Domain"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Domain" end)
  end

  test "a double wildcard on each side of a segment matches once both sides are present" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Billing.Domain.Invoice.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**.Domain.**"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Domain.Invoice" end)
  end

  test "a suffix pattern matches a module under the namespace whose name ends in the suffix" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Billing.NotFoundError.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**Error"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "a suffix pattern does not match the namespace root itself" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Error.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**Error"])
    |> refute_issues()
  end

  test "an exact pattern without a wildcard does not match a nested module" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.Account.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> refute_issues()
  end

  test "a trailing double wildcard does not match the namespace root itself" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.new()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo.**"])
    |> refute_issues()
  end

  test "a bare alias stays silent while a call written through it is reported" do
    """
    defmodule CredoSampleModule do
      alias Acme.Repo

      def run, do: Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo"
      assert issue.message == "A module in this namespace must not reference `Acme.Repo`."
    end)
  end

  test "an unused alias to a forbidden module is not reported" do
    """
    defmodule CredoSampleModule do
      alias Acme.Repo

      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> refute_issues()
  end

  test "a renamed alias stays silent" do
    """
    defmodule CredoSampleModule do
      alias Acme.Repo, as: DataStore

      def run, do: DataStore.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue -> assert issue.trigger == "DataStore" end)
  end

  test "a multi form directive is not resolved into its individual members" do
    """
    defmodule CredoSampleModule do
      import Acme.Repo.{Account, Billing}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo.**"])
    |> refute_issues()
  end

  test "a module named inside a typespec is not reported" do
    """
    defmodule CredoSampleModule do
      @type account :: Acme.Repo.Account.t()

      @spec run(Acme.Repo.Account.t()) :: :ok
      def run(_account), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo.**"])
    |> refute_issues()
  end

  test "code inside a quote block is not analyzed" do
    """
    defmodule Acme.Macros do
      defmacro build do
        quote do
          Acme.Repo.get(1)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> refute_issues()
  end

  test "uses a custom message from a {pattern, message} entry" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: [{"Acme.Repo", "Use the domain context instead of the repository."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Use the domain context instead of the repository."
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"], hint: "Call Acme.Accounts instead.")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "A module in this namespace must not reference `Acme.Repo`. Call Acme.Accounts instead."
    end)
  end

  test "treats a regex metacharacter inside a pattern as a literal character" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Foo.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Foo?"])
    |> refute_issues()
  end

  test "does not report a reference to an Erlang module written as a plain atom" do
    """
    defmodule CredoSampleModule do
      def run, do: :os.system_time()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.**"])
    |> refute_issues()
  end

  test "does not report an ambiguous name as the module it is written as" do
    """
    defmodule A do
      alias Vendor.Client

      def run, do: Client.call()
    end

    defmodule B do
      alias Acme.Client

      def run, do: Client.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Client"])
    |> refute_issues()
  end

  test "reports a module written with an explicit Elixir prefix" do
    """
    defmodule CredoSampleModule do
      def run, do: Elixir.Acme.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Repo"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.Acme.Repo"
      assert issue.message == "A module in this namespace must not reference `Acme.Repo`."
    end)
  end

  test "accepts a plain module name given as an atom" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.Repo.get(1)
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: [Acme.Repo])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Repo" end)
  end

  test "raises when a forbidden pattern is not a binary or a module name" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
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
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid forbidden entry/, fn ->
      NamespaceBoundary.run(source_file, forbidden: [{"Acme.Repo", :not_a_string}])
    end
  end

  test "raises when an except entry carries a message" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid namespace boundary pattern/, fn ->
      NamespaceBoundary.run(source_file,
        forbidden: ["Acme.**"],
        except: [{"Acme.Repo", "The repo is fine here."}]
      )
    end
  end

  test "raises when an except pattern is not a binary or a module name" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid namespace boundary pattern/, fn ->
      NamespaceBoundary.run(source_file, forbidden: ["Acme.**"], except: [123])
    end
  end

  test "is inert when private_to is left as the default empty list" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary)
    |> refute_issues()
  end

  test "is inert when private_to is explicitly set to nil" do
    """
    defmodule CredoSampleModule do
      def run, do: Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: nil)
    |> refute_issues()
  end

  test "does not report a private module referenced from inside its owning namespace" do
    """
    defmodule Acme.BillingService.CreateInvoice do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> refute_issues()
  end

  test "reports a private module referenced from outside its owning namespace" do
    """
    defmodule Acme.Web.InvoiceController do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.BillingService.NotFoundError"

      assert issue.message ==
               "The module `Acme.BillingService.NotFoundError` is private to `Acme.BillingService`."
    end)
  end

  test "reports a private module referenced from a sibling namespace matching the same pattern" do
    """
    defmodule Acme.ShippingService.CreateLabel do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `Acme.BillingService.NotFoundError` is private to `Acme.BillingService`."
    end)
  end

  test "does not report a module that matches the owning prefix but not the private part" do
    """
    defmodule Acme.Web.InvoiceController do
      def run, do: Acme.BillingService.Handler.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> refute_issues()
  end

  test "a pattern that is only the owning prefix makes a namespace private to itself" do
    """
    defmodule Acme.Processor.Shipping do
      def run, do: Acme.Processor.Billing.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.Processor.*)"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `Acme.Processor.Billing` is private to `Acme.Processor.Billing`."
    end)
  end

  test "a namespace private to itself may still reference what is under it" do
    """
    defmodule Acme.Processor.Shipping do
      def run, do: Acme.Processor.Shipping.Step.call()
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.Processor.*)"])
    |> refute_issues()
  end

  test "binds the owning namespace to the longest match a pattern allows" do
    """
    defmodule Acme.Service.Billing.V1.OtherService.Handler do
      def run, do: raise Acme.Service.Billing.V1.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.**.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `Acme.Service.Billing.V1.BillingService.NotFoundError` is private to `Acme.Service.Billing.V1.BillingService`."
    end)
  end

  test "does not report the head of the private module's own definition" do
    """
    defmodule Acme.BillingService.NotFoundError do
      defexception message: "not found"
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> refute_issues()
  end

  test "resolves an alias before deciding whether a reference crosses a privacy boundary" do
    """
    defmodule Acme.Web.InvoiceController do
      alias Acme.BillingService.NotFoundError

      def run, do: raise NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "NotFoundError"

      assert issue.message ==
               "The module `Acme.BillingService.NotFoundError` is private to `Acme.BillingService`."
    end)
  end

  test "accepts a single private_to pattern given on its own" do
    """
    defmodule Acme.Web.InvoiceController do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: "(Acme.*Service).**Error")
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.BillingService.NotFoundError"
    end)
  end

  test "reports a private_to entry with its own message" do
    """
    defmodule Acme.Web.InvoiceController do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: [{"(Acme.*Service).**Error", "Return the service's public error instead."}]
    )
    |> assert_issue(fn issue ->
      assert issue.message == "Return the service's public error instead."
    end)
  end

  test "appends the hint to a privacy issue" do
    """
    defmodule Acme.Web.InvoiceController do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: ["(Acme.*Service).**Error"],
      hint: "See the service boundaries guide."
    )
    |> assert_issue(fn issue ->
      assert issue.message ==
               "The module `Acme.BillingService.NotFoundError` is private to `Acme.BillingService`. See the service boundaries guide."
    end)
  end

  test "carves an exception out of private_to with except" do
    """
    defmodule Acme.Web.InvoiceController do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: ["(Acme.*Service).**Error"],
      except: ["Acme.BillingService.NotFoundError"]
    )
    |> refute_issues()
  end

  test "does not report a privacy violation in a file that defines no module" do
    """
    raise Acme.BillingService.NotFoundError
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> refute_issues()
  end

  test "does not report a privacy violation in a file whose outermost module is not an alias" do
    """
    defmodule Module.concat(Acme, Web) do
      def run, do: raise Acme.BillingService.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> refute_issues()
  end

  test "does not report a reference written inside a quote block" do
    """
    defmodule Acme.Web.InvoiceController do
      defmacro guard do
        quote do
          raise Acme.BillingService.NotFoundError
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, private_to: ["(Acme.*Service).**Error"])
    |> refute_issues()
  end

  test "raises when forbidden and private_to are set together" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid configuration/, fn ->
      NamespaceBoundary.run(source_file,
        forbidden: ["Acme.Repo"],
        private_to: ["(Acme.*Service).**Error"]
      )
    end
  end

  test "raises when a private_to pattern names no owning namespace" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to pattern/, fn ->
      NamespaceBoundary.run(source_file, private_to: ["Acme.*Service.**Error"])
    end
  end

  test "raises when a private_to pattern has something other than a namespace after the prefix" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to pattern/, fn ->
      NamespaceBoundary.run(source_file, private_to: ["(Acme.*Service)Error"])
    end
  end

  test "raises when a private_to pattern is not a binary" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to pattern/, fn ->
      NamespaceBoundary.run(source_file, private_to: [Acme.BillingService])
    end
  end

  test "raises when a private_to entry carries a message that is not a string" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid private_to entry/, fn ->
      NamespaceBoundary.run(source_file, private_to: [{"(Acme.*Service).**Error", :nope}])
    end
  end

  test "reports a reference written in a pattern by default" do
    """
    defmodule CredoSampleModule do
      def run(%Acme.Domain.NotFoundError{}), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Domain.NotFoundError"
    end)
  end

  test "does not report a struct matched in a clause head when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(result) do
        case result do
          {:error, %Acme.Domain.NotFoundError{}} -> :missing
          other -> other
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a struct matched in a function head when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(%Acme.Domain.NotFoundError{} = error) when is_struct(error), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a pattern on the left of a match or a generator when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(result) do
        %Acme.Domain.NotFoundError{} = result

        with %Acme.Domain.ConflictError{} <- result do
          :ok
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a rescue clause when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run do
        :ok
      rescue
        Acme.Domain.NotFoundError -> :missing
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "reports a struct built in expression position when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run, do: {:error, %Acme.Domain.NotFoundError{}}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Domain.NotFoundError"
    end)
  end

  test "reports a raised module when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run, do: raise Acme.Domain.NotFoundError
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Domain.NotFoundError"
    end)
  end

  test "reports the value side of a match and of a generator when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run do
        error = %Acme.Domain.NotFoundError{}

        with :ok <- Acme.Domain.Guard.call() do
          error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "reports a cond condition when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        cond do
          Acme.Domain.Guard.call(value) -> :ok
          true -> :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Domain.Guard"
    end)
  end

  test "reports a receive timeout when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run do
        receive do
          :done -> :ok
        after
          Acme.Domain.Timeouts.default() -> :timeout
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Acme.Domain.Timeouts"
    end)
  end

  test "does not report a receive clause pattern when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run do
        receive do
          %Acme.Domain.NotFoundError{} -> :missing
        after
          1_000 -> :timeout
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "does not report a struct built as a default argument value when in_patterns is false" do
    """
    defmodule CredoSampleModule do
      def run(error \\\\ %Acme.Domain.NotFoundError{}), do: error
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary, forbidden: ["Acme.Domain.**"], in_patterns: false)
    |> refute_issues()
  end

  test "narrows private_to to expression position as well when in_patterns is false" do
    """
    defmodule Acme.Web.InvoiceController do
      def run(result) do
        case result do
          {:error, %Acme.BillingService.NotFoundError{}} -> :missing
          other -> other
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NamespaceBoundary,
      private_to: ["(Acme.*Service).**Error"],
      in_patterns: false
    )
    |> refute_issues()
  end

  test "raises when in_patterns is not a boolean" do
    source_file =
      """
      defmodule CredoSampleModule do
        def run, do: Acme.Repo.get(1)
      end
      """
      |> to_source_file()

    assert_raise ArgumentError, ~r/invalid in_patterns/, fn ->
      NamespaceBoundary.run(source_file, forbidden: ["Acme.Repo"], in_patterns: :nope)
    end
  end
end
