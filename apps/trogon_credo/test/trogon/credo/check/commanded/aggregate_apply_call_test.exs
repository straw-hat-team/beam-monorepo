defmodule Trogon.Credo.Check.Commanded.AggregateApplyCallTest do
  use Credo.Test.Case

  alias Credo.Check.ConfigCommentFinder
  alias Credo.CLI.Filter
  alias Credo.Execution
  alias Trogon.Credo.Check.Commanded.AggregateApplyCall
  alias Trogon.Credo.Check.Commanded.AggregateStateConstruction

  test "still reports issues under the deprecated name" do
    """
    defmodule Acme.Review.Domain.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id
    end

    defmodule Acme.Review.Test do
      alias Acme.Review.Domain.Aggregate

      def run(aggregate, event) do
        Aggregate.apply(aggregate, event)
      end
    end
    """
    |> to_source_file()
    |> run_check(AggregateApplyCall)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Aggregate"
    end)
  end

  test "reports its issues under its own name, with the same category, priority and exit status as the new check" do
    source = """
    defmodule Acme.Review.Domain.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id
    end

    defmodule Acme.Review.Test do
      alias Acme.Review.Domain.Aggregate

      def run(aggregate, event) do
        Aggregate.apply(aggregate, event)
      end
    end
    """

    [old_issue] = source |> to_source_file() |> run_check(AggregateApplyCall)
    [new_issue] = source |> to_source_file() |> run_check(AggregateStateConstruction)

    assert old_issue.check == AggregateApplyCall
    assert new_issue.check == AggregateStateConstruction
    assert old_issue.category == new_issue.category
    assert old_issue.priority == new_issue.priority
    assert old_issue.exit_status == new_issue.exit_status
  end

  test "a disable comment naming the old check suppresses the issue it reports" do
    source_file =
      to_source_file("""
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          # credo:disable-for-next-line Trogon.Credo.Check.Commanded.AggregateApplyCall
          Aggregate.apply(aggregate, event)
        end
      end
      """)

    issues = run_check(source_file, AggregateApplyCall)
    assert issues != []
    assert Filter.valid_issues(issues, config_comment_exec(source_file)) == []
  end

  test "a disable comment naming the old check does not suppress the new check's issue" do
    source_file =
      to_source_file("""
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          # credo:disable-for-next-line Trogon.Credo.Check.Commanded.AggregateApplyCall
          Aggregate.apply(aggregate, event)
        end
      end
      """)

    issues = run_check(source_file, AggregateStateConstruction)
    assert issues != []
    assert Filter.valid_issues(issues, config_comment_exec(source_file)) == issues
  end

  defp config_comment_exec(source_file) do
    config_comment_map =
      [source_file]
      |> ConfigCommentFinder.run()
      |> Enum.into(%{})

    %{Execution.build() | config_comment_map: config_comment_map}
  end

  test "still forwards params to the same rules, such as a struct literal" do
    """
    defmodule Acme.Review.Domain.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id
    end

    defmodule Acme.Review.Test do
      alias Acme.Review.Domain.Aggregate

      def run(attrs) do
        %Aggregate{status: attrs.status}
      end
    end
    """
    |> to_source_file()
    |> run_check(AggregateApplyCall)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Aggregate"
    end)
  end

  test "still forwards configured params, such as a custom constructor_functions entry" do
    """
    defmodule Acme.Review.Domain.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id
    end

    defmodule Acme.Review.Test do
      alias Acme.Review.Domain.Aggregate

      def run(attrs) do
        Aggregate.build(attrs)
      end
    end
    """
    |> to_source_file()
    |> run_check(AggregateApplyCall, constructor_functions: [:build])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Aggregate"
    end)
  end
end
