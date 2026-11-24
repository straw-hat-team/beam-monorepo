defmodule Trogon.Credo.Check.Config.SystemEnvReadTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Config.SystemEnvRead

  @message "Environment variables are read once at boot in config/runtime.exs and passed " <>
             "through application config; a read here happens at compile time or scatters " <>
             "configuration across the code base. Read the value from application config " <>
             "or take it as an argument instead."

  test "reports a qualified call to System.get_env in a lib file" do
    """
    defmodule Acme.Billing do
      def rate, do: System.get_env("TAX_RATE")
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue ->
      assert issue.check == SystemEnvRead
      assert issue.category == SystemEnvRead.category()
      assert issue.trigger == "System.get_env"
      assert issue.message == @message
    end)
  end

  test "reports System.get_env at arity 0" do
    """
    defmodule Acme.Billing do
      def rate do
        System.get_env()
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports System.get_env at arity 2" do
    """
    defmodule Acme.Billing do
      def rate do
        System.get_env("TAX_RATE", "0.0")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports System.fetch_env at arity 1" do
    """
    defmodule Acme.Billing do
      def rate do
        System.fetch_env("TAX_RATE")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.fetch_env" end)
  end

  test "reports System.fetch_env! at arity 1" do
    """
    defmodule Acme.Billing do
      def rate do
        System.fetch_env!("TAX_RATE")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.fetch_env!" end)
  end

  test "reports :os.getenv at arity 0" do
    """
    defmodule Acme.Billing do
      def rate do
        :os.getenv()
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == ":os.getenv" end)
  end

  test "reports :os.getenv at arity 1" do
    """
    defmodule Acme.Billing do
      def rate do
        :os.getenv(~c"TAX_RATE")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == ":os.getenv" end)
  end

  test "reports :os.getenv at arity 2" do
    """
    defmodule Acme.Billing do
      def rate do
        :os.getenv(~c"TAX_RATE", ~c"0.0")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == ":os.getenv" end)
  end

  test "reports :os.env at arity 0" do
    """
    defmodule Acme.Billing do
      def rate do
        :os.env()
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == ":os.env" end)
  end

  test "reports a call through an alias" do
    """
    defmodule Acme.Billing do
      alias System, as: Sys

      def rate, do: Sys.get_env("TAX_RATE")
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "Sys.get_env" end)
  end

  test "reports a piped call" do
    """
    defmodule Acme.Billing do
      def rate do
        "TAX_RATE" |> System.get_env()
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports a captured call" do
    """
    defmodule Acme.Billing do
      def rate do
        &System.get_env/1
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports a capture of an imported function" do
    """
    defmodule Acme.Billing do
      import System, only: [get_env: 1]

      def rate do
        &get_env/1
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
  end

  test "reports a read in the options of a use, not the used module" do
    """
    defmodule Acme.Billing do
      use Acme.Options, value: System.fetch_env!("VALUE")
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue ->
      assert issue.trigger == "System.fetch_env!"
      assert issue.line_no == 2
    end)
  end

  test "does not report a use directive without a read in its options" do
    """
    defmodule Acme.Billing do
      use Acme.Options, value: "VALUE"
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "reports a read in a test file" do
    """
    defmodule Acme.Billing do
      def rate do
        System.get_env("TAX_RATE")
      end
    end
    """
    |> to_source_file("test/billing_test.exs")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports a read in config/config.exs" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("config/config.exs")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports a read in mix.exs by default" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("mix.exs")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "does not report config/runtime.exs" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "does not report an app's config/runtime.exs" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("apps/acme/config/runtime.exs")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "does not report an absolute path to config/runtime.exs" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("/work/acme/config/runtime.exs")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "reports a file whose directory only ends in config" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("myconfig/runtime.exs")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "reports a file whose name only ends in runtime.exs" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("config/myruntime.exs")
    |> run_check(SystemEnvRead)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "does not report a file listed in allowed_files" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("mix.exs")
    |> run_check(SystemEnvRead, allowed_files: [{"mix.exs", "The Mix project file runs at compile time."}])
    |> refute_issues()
  end

  test "reports config/runtime.exs once allowed_files replaces the default" do
    """
    System.get_env("TAX_RATE")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(SystemEnvRead, allowed_files: [{"mix.exs", "The Mix project file runs at compile time."}])
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  for {label, entry} <- [
        {"a bare path", "mix.exs"},
        {"a blank reason", {"mix.exs", ""}},
        {"a whitespace reason", {"mix.exs", "   "}},
        {"a non-string reason", {"mix.exs", :because}},
        {"a non-string path", {:"mix.exs", "Reason."}},
        {"a triple", {"mix.exs", "Reason.", :extra}}
      ] do
    test "raises on an allowed_files entry that is #{label}" do
      entry = unquote(Macro.escape(entry))

      assert_raise ArgumentError, ~r/invalid allowed_files entry .*\{path, reason\}.*postgres\.ex/s, fn ->
        source_file = to_source_file("System.get_env(\"TAX_RATE\")", "lib/acme.ex")
        SystemEnvRead.run(source_file, allowed_files: [entry])
      end
    end
  end

  test "does not report System.put_env" do
    """
    defmodule Acme.Billing do
      def rate do
        System.put_env("TAX_RATE", "0.07")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "does not report System.delete_env" do
    """
    defmodule Acme.Billing do
      def rate do
        System.delete_env("TAX_RATE")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "does not report Application.get_env" do
    """
    defmodule Acme.Billing do
      def rate do
        Application.get_env(:acme, :tax_rate)
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead)
    |> refute_issues()
  end

  test "honors a custom calls list" do
    """
    defmodule Acme.Billing do
      def rate do
        Acme.Env.fetch("TAX_RATE")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead, calls: [{Acme.Env, :fetch}])
    |> assert_issue(fn issue -> assert issue.trigger == "Acme.Env.fetch" end)
  end

  test "does not report a default call once calls is replaced" do
    """
    defmodule Acme.Billing do
      def rate do
        System.get_env("TAX_RATE")
      end
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead, calls: [{Acme.Env, :fetch}])
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Billing do
      def rate, do: System.get_env("TAX_RATE")
    end
    """
    |> to_source_file("lib/acme/billing.ex")
    |> run_check(SystemEnvRead, hint: "Read it through Acme.Config instead.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " Read it through Acme.Config instead." end)
  end
end
