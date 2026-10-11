defmodule Trogon.Credo.Check.Ecto.RepoTransactTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Ecto.RepoTransact

  @message "Compose the transaction with `Ecto.Multi` and run it with `Repo.transaction/2` " <>
             "instead of calling `transact` on a repo."

  test "reports a qualified call to transact on a repo" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Repo.transact(fn -> {:ok, :done} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> assert_issue(fn issue ->
      assert issue.check == RepoTransact
      assert issue.category == RepoTransact.category()
      assert issue.trigger == "MyApp.Repo.transact"
      assert issue.message == @message
    end)
  end

  test "reports transact at every arity" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Repo.transact(fn -> {:ok, :done} end)
        MyApp.Repo.transact(fn -> {:ok, :done} end, timeout: 1_000)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports a call through an alias" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Repo

      def run do
        Repo.transact(fn -> {:ok, :done} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> assert_issue(fn issue -> assert issue.trigger == "Repo.transact" end)
  end

  test "reports a piped call" do
    """
    defmodule CredoSampleModule do
      def run(fun) do
        fun |> MyApp.Repo.transact()
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo.transact" end)
  end

  test "reports a captured call" do
    """
    defmodule CredoSampleModule do
      def run do
        &MyApp.Repo.transact/2
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Repo.transact" end)
  end

  test "reports a repo nested under a namespace by default" do
    """
    defmodule CredoSampleModule do
      def run do
        Acme.Billing.Repo.transact(fn -> {:ok, :done} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> assert_issue()
  end

  test "does not report transaction, whatever it is given" do
    """
    defmodule CredoSampleModule do
      def run(multi) do
        MyApp.Repo.transaction(multi)
        MyApp.Repo.transaction(fn -> :done end, timeout: 1_000)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> refute_issues()
  end

  test "does not report transact on a module that is not a repo" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Ledger.transact(:entry)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact)
    |> refute_issues()
  end

  test "reports only the configured repos when repos is set" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Repo.transact(fn -> {:ok, :done} end)
        MyApp.ReadOnlyRepo.transact(fn -> {:ok, :done} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact, repos: [MyApp.ReadOnlyRepo])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.ReadOnlyRepo.transact" end)
  end

  test "accepts a module name pattern in repos" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.ReadOnlyRepo.transact(fn -> {:ok, :done} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact, repos: ["MyApp.*Repo"])
    |> assert_issue()
  end

  test "appends the hint to the message" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Repo.transact(fn -> {:ok, :done} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(RepoTransact, hint: "See the persistence guide.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " See the persistence guide." end)
  end
end
