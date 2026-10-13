defmodule Trogon.Credo.Check.Ecto.MultiRunRepoTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Ecto.MultiRunRepo

  @message "An `Ecto.Multi.run` callback must use the repo it is given, so its queries run on " <>
             "the connection of the transaction that runs the `Ecto.Multi`."

  test "does not report a callback that uses its repo" do
    """
    defmodule CredoSampleModule do
      def run(multi, id) do
        Ecto.Multi.run(multi, :lock, fn repo, _changes -> {:ok, lock(repo, id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> refute_issues()
  end

  test "reports a callback that ignores its repo with an underscore name" do
    """
    defmodule CredoSampleModule do
      def run(multi, id) do
        Ecto.Multi.run(multi, :lock, fn _repo, _changes -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Ecto.Multi.run"
      assert issue.message == @message
      assert issue.line_no == 3
    end)
  end

  test "reports a callback that ignores its repo with a bare underscore" do
    """
    defmodule CredoSampleModule do
      def run(multi, id) do
        Ecto.Multi.run(multi, :lock, fn _, _ -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> assert_issue()
  end

  test "reports a piped call" do
    """
    defmodule CredoSampleModule do
      def run(multi, id) do
        multi
        |> Ecto.Multi.run(:lock, fn _repo, _changes -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> assert_issue(fn issue -> assert issue.trigger == "Ecto.Multi.run" end)
  end

  test "reports a call through an alias" do
    """
    defmodule CredoSampleModule do
      alias Ecto.Multi

      def run(multi, id) do
        Multi.run(multi, :lock, fn _repo, _changes -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> assert_issue(fn issue -> assert issue.trigger == "Multi.run" end)
  end

  test "does not report run on a module the file aliases as Multi" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Multi

      def run(multi, id) do
        Multi.run(multi, :lock, fn _repo, _changes -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> refute_issues()
  end

  test "reports each clause of a multi-clause callback that ignores its repo" do
    """
    defmodule CredoSampleModule do
      def run(multi) do
        Ecto.Multi.run(multi, :step, fn
          _repo, %{user: nil} -> {:error, :missing}
          repo, %{user: user} -> repo.update(user)
          _repo, _changes -> {:ok, :skipped}
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports a guarded clause that ignores its repo" do
    """
    defmodule CredoSampleModule do
      def run(multi, id) do
        Ecto.Multi.run(multi, :lock, fn _repo, changes when is_map(changes) -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> assert_issue()
  end

  test "does not report a capture" do
    """
    defmodule CredoSampleModule do
      def run(multi) do
        Ecto.Multi.run(multi, :lock, &lock/2)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> refute_issues()
  end

  test "does not report the module, function, and arguments form" do
    """
    defmodule CredoSampleModule do
      def run(multi) do
        multi
        |> Ecto.Multi.run(:lock, __MODULE__, :lock, [])
        |> Ecto.Multi.run(:other, __MODULE__, :other, [])
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo)
    |> refute_issues()
  end

  test "appends the hint to the message when configured" do
    """
    defmodule CredoSampleModule do
      def run(multi, id) do
        Ecto.Multi.run(multi, :lock, fn _repo, _changes -> {:ok, lock(id)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(MultiRunRepo, hint: "Pass the repo down.")
    |> assert_issue(fn issue -> assert issue.message == "#{@message} Pass the repo down." end)
  end
end
