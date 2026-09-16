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

  test "does not report a capture that reaches into its argument" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, & &1.id)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
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

  test "does not report a capture that reaches deeper into its argument" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(& &1.user.id)
        |> Enum.map(& &1[:id])
        |> Enum.map(&label(&1).id)
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "reports a capture that calls the function it is handed" do
    """
    defmodule MyApp.Runner do
      def call(callbacks), do: Enum.map(callbacks, & &1.())
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.trigger == "&"
    end)
  end

  test "does not report a capture of a function called without arguments" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, &Foo.bar())
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "does not report a capture of a function named on a module attribute" do
    """
    defmodule MyApp.Runner do
      @client MyApp.Client

      def call(items), do: Enum.map(items, &@client.fetch(&1))
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "reports a capture that branches instead of naming a function" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&(if &1, do: :ok, else: :error))
        |> Enum.map(&(unless &1, do: :error))
        |> Enum.map(&(case &1 do nil -> :error; value -> value end))
        |> Enum.map(&(cond do &1 -> :ok; true -> :error end))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "reports a capture that loops or handles instead of naming a function" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&(for value <- &1, do: value))
        |> Enum.map(&(with {:ok, value} <- &1, do: value))
        |> Enum.map(&(try do &1.() rescue _ -> :error end))
        |> Enum.map(&(receive do _ -> &1 end))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "reports a capture that quotes instead of naming a function" do
    """
    defmodule MyApp.Runner do
      defmacro call(value), do: quote(do: unquote(value))

      def build(values), do: Enum.map(values, &quote(do: unquote(&1)))
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "does not report a capture of a macro that names what it does" do
    """
    defmodule MyApp.Runner do
      def call(messages) do
        messages
        |> Enum.map(&raise(&1))
        |> Enum.map(&throw(&1))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> refute_issues()
  end

  test "names the identity function when a capture returns its argument" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, & &1)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Prefer `&Function.identity/1` over an anonymous function that returns its argument."
    end)
  end

  test "names the identity function when an anonymous function returns its argument" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, fn value -> value end)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Prefer `&Function.identity/1` over an anonymous function that returns its argument."
    end)
  end

  test "does not name the identity function when a clause guards its argument" do
    """
    defmodule MyApp.Runner do
      def call(items), do: Enum.map(items, fn value when is_integer(value) -> value end)
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issue(fn issue ->
      assert issue.message == "Prefer a named function over an anonymous function."
    end)
  end

  test "does not name the identity function when an argument goes unreturned" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(fn value -> {value} end)
        |> Enum.map(fn value, _index -> value end)
        |> Enum.map(&{&1})
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues ->
      assert length(issues) == 3

      for issue <- issues do
        assert issue.message == "Prefer a named function over an anonymous function."
      end
    end)
  end

  test "reports a capture that branches or loops across several clauses" do
    """
    defmodule MyApp.Runner do
      def call(items) do
        items
        |> Enum.map(&(for value <- &1, other <- value, do: other))
        |> Enum.map(&(for value <- &1, value > 1, do: value))
        |> Enum.map(&(with {:ok, value} <- &1, {:ok, other} <- value, do: other))
        |> Enum.map(&(with {:ok, value} <- &1, do: value, else: (_ -> :error)))
        |> Enum.map(&(receive do value -> value after 0 -> &1 end))
        |> Enum.map(&(try do &1.() rescue _ -> :error after :ok end))
        |> Enum.map(&quote(bind_quoted: [value: &1], do: value))
      end
    end
    """
    |> to_source_file()
    |> run_check(AnonymousFunction)
    |> assert_issues(fn issues -> assert length(issues) == 7 end)
  end
end
