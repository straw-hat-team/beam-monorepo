defmodule Trogon.Credo.Check.Commanded.ErrorConstructionTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Commanded.ErrorConstruction

  @message "Only the context that defines this error builds or raises it; match on it " <>
             "here, or raise an error this context owns."

  test "reports a struct built outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        %Acme.Billing.Domain.NotFoundError{}
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue ->
      assert issue.check == ErrorConstruction
      assert issue.category == ErrorConstruction.category()
      assert issue.trigger == "Acme.Billing.Domain.NotFoundError"
      assert issue.message == @message
    end)
  end

  test "reports a raise outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        raise Acme.Billing.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a call to exception/1 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Acme.Billing.NotFoundError.exception(invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a call through an alias outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      alias Acme.Billing.NotFoundError

      def create(params) do
        raise NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "NotFoundError" end)
  end

  test "does not report an error raised anywhere inside its owning context" do
    """
    defmodule Acme.Billing.Command.RegisterInvoice do
      def decide(nil, _command) do
        raise Acme.Billing.Domain.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a web layer raising its own error" do
    """
    defmodule Acme.Web.InvoiceController do
      def show(conn, %{"id" => id}) do
        raise Acme.Web.NotFoundError, id: id
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a rescue clause outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Acme.Billing.register_invoice(params)
      rescue
        e in Acme.Billing.NotFoundError -> {:error, e}
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a pattern match outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(%Acme.Billing.NotFoundError{} = error) do
        {:error, error}
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a module that is not an error" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Acme.Billing.register_invoice(params)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        raise Acme.Billing.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction, hint: "Rescue it instead.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " Rescue it instead." end)
  end

  test "accepts a custom errors pattern with a deeper owner" do
    """
    defmodule Acme.Billing.Invoices.Web do
      def create(params) do
        raise Acme.Billing.Payments.DeclinedError
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction, errors: ["(Acme.*.*).**Error"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Payments.DeclinedError" end)
  end

  test "reports a struct update built outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(error) do
        %Acme.Billing.NotFoundError{error | invoice_id: 1}
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a reraise outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        reraise Acme.Billing.NotFoundError, [id: params.id], __STACKTRACE__
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a call to new/1 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Acme.Billing.NotFoundError.new(invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a pipe into exception/1 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        [invoice_id: params.id] |> Acme.Billing.NotFoundError.exception()
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a capture of new/1 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Enum.map(params, &Acme.Billing.NotFoundError.new/1)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports struct!/2 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        struct!(Acme.Billing.NotFoundError, invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports Kernel.struct/2 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Kernel.struct(Acme.Billing.NotFoundError, invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end

  test "reports a raise through an alias given with as:" do
    """
    defmodule Acme.Web.InvoiceController do
      alias Acme.Billing.NotFoundError, as: InvoiceNotFound

      def create(params) do
        raise InvoiceNotFound
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "InvoiceNotFound" end)
  end

  test "does not report is_exception/2 outside the owning context" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(e) do
        is_exception(e, Acme.Billing.NotFoundError)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a call to another function on the error module" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(e) do
        Acme.Billing.NotFoundError.message(e)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report the module passed around as a plain value" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(e) do
        {:error, Acme.Billing.NotFoundError}
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report match?/2 matching the error as a pattern" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(e) do
        match?(%Acme.Billing.NotFoundError{}, e)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a guard matching the error" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(e) when is_struct(e, Acme.Billing.NotFoundError) do
        e
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a case clause pattern matching the error" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(e) do
        case e do
          %Acme.Billing.NotFoundError{} -> :not_found
          _other -> :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "does not report a reference inside a quote block" do
    """
    defmodule Acme.Web.InvoiceMacro do
      defmacro build do
        quote do
          raise Acme.Billing.NotFoundError
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction)
    |> refute_issues()
  end

  test "accepts a custom constructors list that replaces the default" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Acme.Billing.NotFoundError.exception(invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction, constructors: [:build])
    |> refute_issues()
  end

  test "reports a custom constructor named through constructors" do
    """
    defmodule Acme.Web.InvoiceController do
      def create(params) do
        Acme.Billing.NotFoundError.build(invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(ErrorConstruction, constructors: [:build])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.NotFoundError" end)
  end
end
