defmodule Trogon.Credo.Check.Refactor.AnonymousFunctionTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Refactor.AnonymousFunction

  test "does not report a module without an anonymous function" do
    """
    defmodule MyApp.Aliases do
      def merge(aliases, name, target) do
        Map.update(aliases, name, target, &merge_target(&1, target))
      end

      defp merge_target(target, target), do: target
      defp merge_target(_existing, _target), do: :ambiguous
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "does not report a capture" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.pad_leading(&1, 2, "0"))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "reports a single clause anonymous function" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, fn item -> item.id end)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue ->
      assert issue.trigger == "fn"
      assert issue.message == "Prefer a named function over an anonymous function."
      assert issue.line_no == 2
    end)
  end

  test "reports an anonymous function without arguments" do
    """
    defmodule MyApp.Runner do
      def call, do: Task.async(fn -> work() end)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue()
  end

  test "reports a multi clause anonymous function once" do
    """
    defmodule MyApp.Aliases do
      def merge(aliases, name, target) do
        Map.update(aliases, name, target, fn
          ^target -> target
          _other -> :ambiguous
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "reports each anonymous function in a file" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(fn item -> item.id end)
        |> Enum.each(fn id -> log(id) end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports an anonymous function nested in another one" do
    """
    defmodule MyApp.Runner do
      def call(groups) do
        Enum.map(groups, fn group -> Enum.map(group, fn item -> item.id end) end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports an anonymous function written inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro build do
        quote do
          Enum.map(@items, fn item -> item.id end)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue()
  end

  test "does not report a single clause anonymous function when a clause is allowed" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, fn item -> item.id end)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: 1)
    |> refute_issues()
  end

  test "reports a multi clause anonymous function when a single clause is allowed" do
    """
    defmodule MyApp.Aliases do
      def merge(aliases, name, target) do
        Map.update(aliases, name, target, fn
          ^target -> target
          _other -> :ambiguous
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: 1)
    |> assert_issue()
  end

  test "reports a body of several expressions when a single expression is allowed" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        Enum.each(items, fn item ->
          log(item)
          send(item)
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: 1)
    |> assert_issue()
  end

  test "does not report a body of several expressions when body size is left alone" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        Enum.each(items, fn item ->
          log(item)
          send(item)
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: :infinity)
    |> refute_issues()
  end

  test "counts the widest clause body of a multi clause anonymous function" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        Enum.map(items, fn
          %{id: id} ->
            log(id)
            id

          other ->
            other
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 2, max_expressions: 1)
    |> assert_issue()
  end

  test "does not report an anonymous function with a guard when a clause is allowed" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        Enum.map(items, fn item when is_integer(item) -> item + 1 end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: 1)
    |> refute_issues()
  end

  test "does not report a capture that names a function" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.pad_leading/3)
        |> Enum.map(&:erlang.phash2/1)
        |> Enum.map(&pad(&1, 2))
        |> Enum.map(&String.trim(&1, "0"))
        |> Enum.map(&:erlang.phash2(&1, 8))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "reports a capture that reaches into its argument" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, & &1.id)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "reports a capture built out of operators" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&(&1 * 2))
        |> Enum.filter(&(&1 in [2, 4]))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports a capture that only builds a term" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&{&1, &1})
        |> Enum.map(&[&1])
        |> Enum.map(&%{id: &1})
        |> Enum.map(& &1)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "does not count an argument position as an anonymous function" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, &pad(&1, &2))
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "does not report a capture that names no function when a clause is allowed" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, & &1.id)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: 1)
    |> refute_issues()
  end

  test "counts the expressions of a capture body" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, &(log(&1); &1))
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction, max_clauses: 1, max_expressions: 1)
    |> assert_issue()
  end
end
