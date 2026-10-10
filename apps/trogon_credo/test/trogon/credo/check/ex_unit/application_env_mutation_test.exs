defmodule Trogon.Credo.Check.ExUnit.ApplicationEnvMutationTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.ExUnit.ApplicationEnvMutation

  @message "Application env is global to the node; a test that writes it here changes " <>
             "config for every test running at the same time. Pass the config in as an " <>
             "argument, or read it through a seam the test can stub, instead of mutating " <>
             "it directly."

  test "reports a qualified call to Application.put_env in a test file" do
    """
    defmodule Acme.BillingTest do
      test "charges the configured tax rate" do
        Application.put_env(:acme, :tax_rate, 0.07)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue ->
      assert issue.check == ApplicationEnvMutation
      assert issue.category == ApplicationEnvMutation.category()
      assert issue.trigger == "Application.put_env"
      assert issue.message == @message
    end)
  end

  test "reports a file under test/support" do
    """
    defmodule Acme.Test.Support.ConfigFixtures do
      def set_tax_rate(rate), do: Application.put_env(:acme, :tax_rate, rate)
    end
    """
    |> to_source_file("test/support/config_fixtures.ex")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue()
  end

  test "does not report a lib file" do
    """
    defmodule Acme.Billing do
      def start(rate), do: Application.put_env(:acme, :tax_rate, rate)
    end
    """
    |> to_source_file("billing.ex")
    |> run_check(ApplicationEnvMutation)
    |> refute_issues()
  end

  test "reports Application.put_all_env in a test file" do
    """
    defmodule Acme.BillingTest do
      test "sets several keys at once" do
        Application.put_all_env(acme: [tax_rate: 0.07])
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "Application.put_all_env" end)
  end

  test "reports Application.delete_env in a test file" do
    """
    defmodule Acme.BillingTest do
      test "clears the configured tax rate" do
        Application.delete_env(:acme, :tax_rate)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "Application.delete_env" end)
  end

  test "reports the Erlang :application.set_env in a test file" do
    """
    defmodule Acme.BillingTest do
      test "sets the configured tax rate" do
        :application.set_env(:acme, :tax_rate, 0.07)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == ":application.set_env" end)
  end

  test "reports the Erlang :application.unset_env in a test file" do
    """
    defmodule Acme.BillingTest do
      test "clears the configured tax rate" do
        :application.unset_env(:acme, :tax_rate)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == ":application.unset_env" end)
  end

  test "reports a call through an alias in a test file" do
    """
    defmodule Acme.BillingTest do
      alias Application, as: App

      test "charges the configured tax rate" do
        App.put_env(:acme, :tax_rate, 0.07)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "App.put_env" end)
  end

  test "reports a piped call in a test file" do
    """
    defmodule Acme.BillingTest do
      test "charges the configured tax rate" do
        :acme |> Application.put_env(:tax_rate, 0.07)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "Application.put_env" end)
  end

  test "reports a captured call in a test file" do
    """
    defmodule Acme.BillingTest do
      test "charges the configured tax rate" do
        &Application.put_env/3
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "Application.put_env" end)
  end

  test "does not report Application.get_env in a test file" do
    """
    defmodule Acme.BillingTest do
      test "reads the configured tax rate" do
        Application.get_env(:acme, :tax_rate)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.BillingTest do
      test "charges the configured tax rate" do
        Application.put_env(:acme, :tax_rate, 0.07)
      end
    end
    """
    |> to_source_file("billing_test.exs")
    |> run_check(ApplicationEnvMutation, hint: "Read it through Acme.Config instead.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " Read it through Acme.Config instead." end)
  end
end
