defmodule Trogon.Credo.Check.Warning.UnpinnedDependencyTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.UnpinnedDependency

  test "ignores files that are not mix.exs" do
    """
    defmodule CredoSampleModule do
      defp deps do
        [
          {:some_dep, "~> 0.5.0"}
        ]
      end
    end
    """
    |> to_source_file("some_module.ex")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a dependency pinned to a full commit sha" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, git: "https://example.com/some_dep.git", ref: "abcdef0123456789abcdef0123456789abcdef01"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a dependency pinned to an exact hex version" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, "1.2.3"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a dependency not listed in the deps param" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, "~> 0.5.0"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:other_dep])
    |> refute_issues()
  end

  test "reports a hex dependency using an operator requirement" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, "~> 0.5.0"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.trigger == "some_dep"
      assert issue.message =~ "use an exact version"
    end)
  end

  test "reports a hex dependency using an operator requirement with opts" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, ">= 1.0.0", only: :test}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.message =~ "use an exact version"
    end)
  end

  test "reports a git dependency pinned with branch:" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, git: "https://example.com/some_dep.git", branch: "main"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.message =~ "replace `branch:`"
    end)
  end

  test "reports a git dependency pinned with tag:" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, github: "some_org/some_dep", tag: "v1.0.0"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.message =~ "replace `tag:`"
    end)
  end

  test "reports a git dependency with no ref:" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, git: "https://example.com/some_dep.git"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.message =~ "add `ref:`"
    end)
  end

  test "reports a git dependency pinned with a short sha" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, git: "https://example.com/some_dep.git", ref: "abc1234"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.message =~ "use a full 40 character commit sha"
    end)
  end

  test "uses a custom message when configured" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, "~> 0.5.0"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [{:some_dep, "Pin some_dep for reproducible builds."}])
    |> assert_issue(fn issue ->
      assert issue.message =~ "Pin some_dep for reproducible builds."
      assert issue.message =~ "use an exact version"
    end)
  end

  test "reports the 3-element tuple form with a hex requirement" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, "~> 0.5.0", only: :test}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue ->
      assert issue.message =~ "use an exact version"
    end)
  end

  test "does not report the 3-element tuple form pinned to an exact hex version" do
    """
    defmodule Mix.Project do
      defp deps do
        [
          {:some_dep, "1.2.3", only: :test}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "reports a two segment hex version" do
    """
    defmodule MyApp.MixProject do
      defp deps do
        [
          {:some_dep, "1.2"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> assert_issue(fn issue -> assert issue.message =~ "use an exact version" end)
  end

  test "does not report a mix alias sharing a name with a configured dependency" do
    """
    defmodule MyApp.MixProject do
      defp aliases do
        [
          some_dep: ["cmd --some-flag"]
        ]
      end

      defp deps do
        [
          {:some_dep, "1.2.3"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a git dependency whose ref is not a literal string" do
    """
    defmodule MyApp.MixProject do
      @some_dep_sha "abcdef0123456789abcdef0123456789abcdef01"

      defp deps do
        [
          {:some_dep, git: "https://example.com/some_dep.git", ref: @some_dep_sha}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report an exact hex version carrying a pre-release" do
    """
    defmodule MyApp.MixProject do
      defp deps do
        [
          {:some_dep, "1.2.3-rc.1"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a path dependency" do
    """
    defmodule MyApp.MixProject do
      defp deps do
        [
          {:some_dep, path: "../some_dep"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report an umbrella dependency" do
    """
    defmodule MyApp.MixProject do
      defp deps do
        [
          {:some_dep, in_umbrella: true}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a hex dependency pinned with an equality operator" do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      defp deps do
        [
          {:some_dep, "== 0.5.0"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end

  test "does not report a requirement that is only known at compile time" do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      defp deps do
        [
          {:some_dep, @some_dep_version, only: :test}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(UnpinnedDependency, deps: [:some_dep])
    |> refute_issues()
  end
end
