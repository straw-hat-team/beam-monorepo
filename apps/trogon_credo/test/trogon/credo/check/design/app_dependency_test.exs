defmodule Trogon.Credo.Check.Design.AppDependencyTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Design.AppDependency

  test "is inert when nothing is forbidden" do
    """
    defmodule Acme.Core.MixProject do
      use Mix.Project

      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency)
    |> refute_issues()
  end

  test "ignores files that are not mix.exs" do
    """
    defmodule Acme.Core do
      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("lib/acme/core.ex")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> refute_issues()
  end

  test "reports a forbidden dependency named as an atom" do
    """
    defmodule Acme.Core.MixProject do
      use Mix.Project

      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
      assert issue.line_no == 6
      assert issue.message == "This application must not depend on `:acme_web`."
    end)
  end

  test "does not report a dependency that is not forbidden" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:jason, "~> 1.4"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> refute_issues()
  end

  test "reports a forbidden dependency matched by a pattern" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "reports a forbidden dependency declared with a requirement and options" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, "~> 1.0", only: :test}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
    end)
  end

  test "reports a forbidden dependency declared with only a requirement" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, "~> 1.0"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
    end)
  end

  test "reports every forbidden dependency of a list" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, path: "../acme_web"},
          {:jason, "~> 1.4"},
          {:acme_admin, path: "../acme_admin"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) |> Enum.sort() == ["acme_admin", "acme_web"]
    end)
  end

  test "reports a forbidden dependency with its own message" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency,
      forbidden: [{:acme_web, "The core application is the one the web one depends on."}]
    )
    |> assert_issue(fn issue ->
      assert issue.message == "The core application is the one the web one depends on."
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web], hint: "Move the shared code into `:acme_core`.")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "This application must not depend on `:acme_web`. Move the shared code into `:acme_core`."
    end)
  end

  test "does not report a dependency named in except" do
    """
    defmodule Acme.Worker.MixProject do
      defp deps do
        [
          {:acme_core, path: "../acme_core"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"], except: [:acme_core])
    |> refute_issues()
  end

  test "does not report a dependency matched by an except pattern" do
    """
    defmodule Acme.Worker.MixProject do
      defp deps do
        [
          {:acme_core_schema, path: "../acme_core_schema"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"], except: ["acme_core*"])
    |> refute_issues()
  end

  test "reports a forbidden dependency that no except pattern names" do
    """
    defmodule Acme.Worker.MixProject do
      defp deps do
        [
          {:acme_core, path: "../acme_core"},
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"], except: [:acme_core])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "accepts except set to nil" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web], except: nil)
    |> assert_issue()
  end

  test "does not read a keyword list that is not a deps function" do
    """
    defmodule Acme.Core.MixProject do
      defp aliases do
        [
          {:acme_web, "run something"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> refute_issues()
  end

  test "does not read the options of a dependency as dependencies of their own" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:jason, path: "../acme_web", only: [:dev]}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["*"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "jason"
    end)
  end

  test "reads a dependency whose requirement is not written literally" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, @web_requirement}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "reads a dependency whose options are not written literally" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, "~> 1.0", @dev_options}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
      assert issue.line_no == 4
    end)
  end

  test "reads a dependency declared in a clause of a conditional" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        case Mix.env() do
          :dev -> [{:acme_web, "~> 1.0"}]
          _ -> []
        end
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["*"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "does not read the keyword arguments of a call in the body" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [{:acme_web, "~> 1.0"}] ++ extra(only: [:dev], runtime: false)
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["*"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "does not read a keyword list written beside the dependency list" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        options = [only: [:dev], runtime: false]

        [
          {:acme_web, "~> 1.0", options}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["*"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "reads a dependency list built from several" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [{:acme_web, "~> 1.0"}] ++ [{:acme_admin, "~> 1.0"}]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["acme_web", "acme_admin"]
    end)
  end

  test "reads a dependency declared inside a conditional" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        if Mix.env() == :dev do
          [{:acme_web, "~> 1.0"}]
        else
          []
        end
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue(fn issue ->
      assert issue.trigger == "acme_web"
    end)
  end

  test "does not read the options of a dependency whose name is not written as an atom" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {@web_app, path: "../acme_web", only: [:dev]},
          {@web_app, @web_requirement, only: [:dev]}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["*"])
    |> refute_issues()
  end

  test "does not report a dependency whose name is not written as an atom" do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {@web_app, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: ["acme_*"])
    |> refute_issues()
  end

  test "reads a deps function written with a public definition" do
    """
    defmodule Acme.Core.MixProject do
      def deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(AppDependency, forbidden: [:acme_web])
    |> assert_issue()
  end

  test "raises when a forbidden entry is neither a pattern nor a dependency name" do
    source_file = mix_exs()

    assert_raise ArgumentError, ~r/invalid forbidden entry 123/, fn ->
      AppDependency.run(source_file, forbidden: [123])
    end
  end

  test "raises when a {pattern, message} entry's message is not a string" do
    source_file = mix_exs()

    assert_raise ArgumentError, ~r/invalid forbidden entry/, fn ->
      AppDependency.run(source_file, forbidden: [{"acme_*", :not_a_string}])
    end
  end

  test "raises when an except entry carries a message" do
    source_file = mix_exs()

    assert_raise ArgumentError, ~r/invalid except entry/, fn ->
      AppDependency.run(source_file,
        forbidden: ["acme_*"],
        except: [{:acme_core, "The core application is shared."}]
      )
    end
  end

  defp mix_exs do
    """
    defmodule Acme.Core.MixProject do
      defp deps do
        [
          {:acme_web, path: "../acme_web"}
        ]
      end
    end
    """
    |> to_source_file("mix.exs")
  end
end
