defmodule Trogon.Credo.Check.Commanded.DomainErrorConstructionTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Commanded.DomainErrorConstruction

  @message "A domain error is raised by the domain and the command that decided it; " <>
             "match on it here instead of constructing or raising it."

  test "reports a struct built outside the domain and command layers" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(params) do
        %Acme.Billing.Domain.NotFoundError{}
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> assert_issue(fn issue ->
      assert issue.check == DomainErrorConstruction
      assert issue.category == DomainErrorConstruction.category()
      assert issue.trigger == "Acme.Billing.Domain.NotFoundError"
      assert issue.message == @message
    end)
  end

  test "reports a raise outside the domain and command layers" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(params) do
        raise Acme.Billing.Domain.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Domain.NotFoundError" end)
  end

  test "reports a call to exception/1 outside the domain and command layers" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(params) do
        Acme.Billing.Domain.NotFoundError.exception(invoice_id: params.id)
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Domain.NotFoundError" end)
  end

  test "does not report a struct built inside the domain namespace" do
    """
    defmodule Acme.Billing.Domain.Invoice do
      def find!(nil) do
        raise Acme.Billing.Domain.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> refute_issues()
  end

  test "does not report a struct built inside the command layer" do
    """
    defmodule Acme.Billing.Command.RegisterInvoice do
      def decide(nil, _command) do
        raise Acme.Billing.Domain.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> refute_issues()
  end

  test "does not report a rescue clause outside the domain and command layers" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(params) do
        Acme.Billing.register_invoice(params)
      rescue
        e in Acme.Billing.Domain.NotFoundError -> {:error, e}
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> refute_issues()
  end

  test "does not report a pattern match outside the domain and command layers" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(%Acme.Billing.Domain.NotFoundError{} = error) do
        {:error, error}
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(params) do
        raise Acme.Billing.Domain.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction, hint: "Rescue it instead.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " Rescue it instead." end)
  end

  test "accepts a custom errors pattern" do
    """
    defmodule Acme.Billing.Web.InvoiceController do
      def create(params) do
        raise Acme.Billing.Failure
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction, errors: ["Acme.**.Failure"])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Billing.Failure" end)
  end

  test "accepts a custom constructed_in list" do
    """
    defmodule Acme.Billing.Support.Invoice do
      def find!(nil) do
        raise Acme.Billing.Domain.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(DomainErrorConstruction, constructed_in: ["**.Domain", "**.Domain.**", "**.Support.**"])
    |> refute_issues()
  end
end
