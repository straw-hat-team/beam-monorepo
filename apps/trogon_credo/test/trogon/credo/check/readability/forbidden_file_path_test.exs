defmodule Trogon.Credo.Check.Readability.ForbiddenFilePathTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.ForbiddenFilePath

  @source """
  defmodule MyApp.Fixture do
  end
  """

  defp run(path, params) do
    @source
    |> to_source_file(path)
    |> run_check(ForbiddenFilePath, params)
  end

  describe "inert by default" do
    test "is silent when unconfigured" do
      "test/fixtures/thing.ex" |> run([]) |> refute_issues()
    end

    test "is silent when forbidden is an empty list" do
      "test/fixtures/thing.ex" |> run(forbidden: []) |> refute_issues()
    end

    test "is silent when forbidden is explicitly nil" do
      "test/fixtures/thing.ex" |> run(forbidden: nil) |> refute_issues()
    end
  end

  describe "the test/support convention" do
    @config [
      forbidden: [{"test/**/*.ex", "A compile-time test file must live in `test/support`."}],
      except: ["test/support/**"]
    ]

    test "reports a compile-time file outside test/support" do
      "test/fixtures/thing.ex"
      |> run(@config)
      |> assert_issue(fn issue ->
        assert issue.message == "A compile-time test file must live in `test/support`."
        assert issue.line_no == 1
      end)
    end

    test "reports a compile-time file directly under test" do
      "test/thing.ex" |> run(@config) |> assert_issue()
    end

    test "reports a compile-time file nested several directories deep" do
      "test/a/b/c/thing.ex" |> run(@config) |> assert_issue()
    end

    test "is silent on a file under test/support" do
      "test/support/thing.ex" |> run(@config) |> refute_issues()
    end

    test "is silent on a file nested under test/support" do
      "test/support/proto/thing.ex" |> run(@config) |> refute_issues()
    end

    test "is silent on a test script, since the pattern names the compiled extension" do
      "test/thing_test.exs" |> run(@config) |> refute_issues()
    end

    test "is silent on a file outside the forbidden tree" do
      "lib/my_app/thing.ex" |> run(@config) |> refute_issues()
    end
  end

  describe "wildcards" do
    test "a single wildcard does not cross a path separator" do
      "test/a/thing.ex" |> run(forbidden: ["test/*.ex"]) |> refute_issues()
    end

    test "a single wildcard matches within one segment" do
      "test/thing.ex" |> run(forbidden: ["test/*.ex"]) |> assert_issue()
    end

    test "a double wildcard matches zero segments" do
      "test/thing.ex" |> run(forbidden: ["test/**/*.ex"]) |> assert_issue()
    end

    test "a double wildcard matches several segments" do
      "test/a/b/thing.ex" |> run(forbidden: ["test/**/*.ex"]) |> assert_issue()
    end

    test "a single wildcard matches one app directory segment" do
      "apps/my_app/test/thing.ex" |> run(forbidden: ["apps/*/test/**/*.ex"]) |> assert_issue()
    end

    test "a single wildcard does not span two path segments" do
      "apps/my_app/nested/test/thing.ex"
      |> run(forbidden: ["apps/*/test/**/*.ex"])
      |> refute_issues()
    end

    test "a pattern is anchored at both ends" do
      "vendor/test/thing.ex" |> run(forbidden: ["test/**/*.ex"]) |> refute_issues()
    end

    test "a dot in a pattern is literal rather than regex syntax" do
      "test/thingXex" |> run(forbidden: ["test/*.ex"]) |> refute_issues()
    end
  end

  describe "messages" do
    test "falls back to a default message naming the path" do
      "test/fixtures/thing.ex"
      |> run(forbidden: ["test/**/*.ex"])
      |> assert_issue(fn issue ->
        assert issue.message == "A file must not live at `test/fixtures/thing.ex`."
      end)
    end

    test "appends a hint to a default message" do
      "test/fixtures/thing.ex"
      |> run(forbidden: ["test/**/*.ex"], hint: "Move it to `test/support`.")
      |> assert_issue(fn issue ->
        assert issue.message ==
                 "A file must not live at `test/fixtures/thing.ex`. Move it to `test/support`."
      end)
    end

    test "appends a hint to a custom message" do
      "test/fixtures/thing.ex"
      |> run(forbidden: [{"test/**/*.ex", "Wrong place."}], hint: "Move it to `test/support`.")
      |> assert_issue(fn issue ->
        assert issue.message == "Wrong place. Move it to `test/support`."
      end)
    end

    test "the first matching forbidden entry wins" do
      "test/fixtures/thing.ex"
      |> run(forbidden: [{"test/**/*.ex", "First."}, {"test/fixtures/*.ex", "Second."}])
      |> assert_issue(fn issue -> assert issue.message == "First." end)
    end
  end

  describe "except" do
    test "an except pattern suppresses a forbidden match" do
      "test/support/thing.ex"
      |> run(forbidden: ["test/**/*.ex"], except: ["test/support/**"])
      |> refute_issues()
    end

    test "an explicitly nil except is treated as no exception" do
      "test/fixtures/thing.ex"
      |> run(forbidden: ["test/**/*.ex"], except: nil)
      |> assert_issue()
    end

    test "an except pattern that does not match leaves the report in place" do
      "test/fixtures/thing.ex"
      |> run(forbidden: ["test/**/*.ex"], except: ["test/support/**"])
      |> assert_issue()
    end
  end

  describe "malformed configuration" do
    test "raises when a pattern is not a string" do
      source_file = to_source_file(@source, "test/fixtures/thing.ex")

      assert_raise ArgumentError, fn ->
        ForbiddenFilePath.run(source_file, forbidden: [:"test/**/*.ex"])
      end
    end

    test "raises when a tuple carries a non-string message" do
      source_file = to_source_file(@source, "test/fixtures/thing.ex")

      assert_raise ArgumentError, fn ->
        ForbiddenFilePath.run(source_file, forbidden: [{"test/**/*.ex", :nope}])
      end
    end

    test "raises when an except pattern is not a string" do
      source_file = to_source_file(@source, "test/fixtures/thing.ex")

      assert_raise ArgumentError, fn ->
        ForbiddenFilePath.run(source_file, forbidden: ["test/**/*.ex"], except: [:nope])
      end
    end
  end
end
