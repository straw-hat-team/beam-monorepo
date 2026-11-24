defmodule Trogon.Credo.Check.Warning.ApplicationEnvReadTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.ApplicationEnvRead

  @call_message "Application env read directly bypasses the project's facade, so a test " <>
                  "cannot mock it and has to mutate the global application env. Read it " <>
                  "through the facade instead."

  @reference_message "The `Application` module used as a value is the target of a dynamic call " <>
                       "that bypasses the project's facade, so a test cannot mock it and has " <>
                       "to mutate the global application env. Read application env through " <>
                       "the facade instead."

  describe "calls" do
    test "reports a qualified call" do
      """
      defmodule Acme.Billing do
        def rate, do: Application.get_env(:acme, :tax_rate)
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue ->
        assert issue.check == ApplicationEnvRead
        assert issue.category == ApplicationEnvRead.category()
        assert issue.trigger == "Application.get_env"
        assert issue.message == @call_message
        assert issue.line_no == 2
      end)
    end

    for {call, args} <- [
          {"get_env", ":acme, :key"},
          {"get_env", ":acme, :key, 0"},
          {"fetch_env", ":acme, :key"},
          {"fetch_env!", ":acme, :key"},
          {"get_all_env", ":acme"}
        ] do
      test "reports Application.#{call}(#{args})" do
        call = unquote(call)

        """
        defmodule Acme.Billing do
          def rate, do: Application.#{call}(#{unquote(args)})
        end
        """
        |> to_source_file("lib/acme/billing.ex")
        |> run_check(ApplicationEnvRead)
        |> assert_issue(fn issue -> assert issue.trigger == "Application.#{call}" end)
      end
    end

    test "reports a call through an alias" do
      """
      defmodule Acme.Billing do
        alias Elixir.Application, as: App

        def rate, do: App.get_env(:acme, :tax_rate)
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "App.get_env" end)
    end

    test "reports a call written with the Elixir prefix" do
      """
      defmodule Acme.Billing do
        def rate, do: Elixir.Application.get_env(:acme, :tax_rate)
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue()
    end

    test "reports a piped call once" do
      """
      defmodule Acme.Billing do
        def rate(app), do: app |> Application.get_all_env()
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Application.get_all_env" end)
    end

    test "reports a capture once" do
      """
      defmodule Acme.Billing do
        def reader, do: &Application.get_env/2
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Application.get_env" end)
    end

    test "reports an imported bare call" do
      """
      defmodule Acme.Billing do
        import Application, only: [get_env: 2]

        def rate, do: get_env(:acme, :tax_rate)
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "get_env" end)
    end

    for {call, args} <- [
          {"get_env", ":acme"},
          {"get_env", ":acme, :key"},
          {"get_env", ":acme, :key, 0"},
          {"get_all_env", ""},
          {"get_all_env", ":acme"}
        ] do
      test "reports :application.#{call}(#{args})" do
        call = unquote(call)

        """
        defmodule Acme.Billing do
          def rate, do: :application.#{call}(#{unquote(args)})
        end
        """
        |> to_source_file("lib/acme/billing.ex")
        |> run_check(ApplicationEnvRead)
        |> assert_issue(fn issue -> assert issue.trigger == ":application.#{call}" end)
      end
    end

    test "reports a read in the options of a use" do
      """
      defmodule Acme.Billing do
        use Acme.Options, rate: Application.fetch_env!(:acme, :tax_rate)
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Application.fetch_env!" end)
    end

    test "does not report compile_env or compile_env!" do
      """
      defmodule Acme.Billing do
        @rate Application.compile_env(:acme, :tax_rate)
        @rate_default Application.compile_env(:acme, :tax_rate, 0.0)
        @rate_bang Application.compile_env!(:acme, :tax_rate)
        @rate_piped :acme |> Application.compile_env(:tax_rate)
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report the facade module" do
      ~S'''
      defmodule Acme do
        @application Application.compile_env(:acme, [__MODULE__, :application], Application)

        defdelegate get_env(app, key, default \\ nil), to: @application
        defdelegate fetch_env!(app, key), to: @application
      end
      '''
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report writes, lifecycle, or introspection" do
      """
      defmodule Acme.Billing do
        def run do
          Application.put_env(:acme, :key, 1)
          Application.delete_env(:acme, :key)
          Application.ensure_all_started(:acme)
          Application.spec(:acme, :vsn)
          Application.app_dir(:acme)
          Application.started_applications()
          Application.get_application(__MODULE__)
          :application.set_env(:acme, :key, 1)
          :application.get_key(:acme, :vsn)
        end
      end
      """
      |> to_source_file("lib/acme/billing.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end
  end

  describe "module references" do
    test "reports Application as the default of a Keyword.pop" do
      """
      defmodule Acme.Client do
        def call(app, key, opts) do
          {application, opts} = Keyword.pop(opts, :application, Application)
          application.get_env(app, key, opts)
        end
      end
      """
      |> to_source_file("lib/acme/client.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue ->
        assert issue.check == ApplicationEnvRead
        assert issue.trigger == "Application"
        assert issue.message == @reference_message
        assert issue.line_no == 3
      end)
    end

    test "reports Application bound to a variable" do
      """
      defmodule Acme.Client do
        def module do
          mod = Application
          mod
        end
      end
      """
      |> to_source_file("lib/acme/client.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Application" end)
    end

    test "reports a defdelegate to Application" do
      """
      defmodule Acme do
        defdelegate get_env(app, key, default), to: Application
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Application" end)
    end

    test "reports Elixir.Application" do
      """
      defmodule Acme do
        def module, do: Elixir.Application
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Elixir.Application" end)
    end

    test "reports Application through an alias" do
      """
      defmodule Acme do
        alias Elixir.Application, as: App

        def module, do: App
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "App" end)
    end

    test "reports one issue for a reference and one for a call beside it" do
      """
      defmodule Acme do
        def run(opts) do
          Application.get_env(:acme, :key)
          Keyword.get(opts, :application, Application)
        end
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() == ["Application", "Application.get_env"]
      end)
    end

    test "does not report the call target as a reference" do
      """
      defmodule Acme do
        def run, do: Application.get_env(:acme, :key)
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> assert_issue(fn issue -> assert issue.trigger == "Application.get_env" end)
    end

    test "does not report Application inside compile_env arguments" do
      """
      defmodule Acme do
        @a Application.compile_env(:acme, :application, Application)
        @b Application.compile_env!(:acme, [Acme, :application])
        @c Application.compile_env(:acme, [Acme, :application], Elixir.Application)
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report alias, import, require, or use directives" do
      """
      defmodule Acme do
        use Application
        alias Application, as: App
        alias Elixir.Application
        import Application, only: [put_env: 3]
        require Application
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report typespecs, behaviour, or impl" do
      """
      defmodule Acme do
        @behaviour Application
        @type t :: Application.t()
        @typep p :: Application.app()
        @opaque o :: Application.t()
        @callback cb(Application.app()) :: Application.t()
        @macrocallback mcb(Application.app()) :: Application.t()
        @spec run(Application.app()) :: Application.t()
        @impl Application
        def run(app), do: app
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report MyApp.Application" do
      """
      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = []
          Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
        end
      end
      """
      |> to_source_file("lib/my_app/application.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report a reference to another module named Application" do
      """
      defmodule Acme do
        alias MyApp.Application

        def application, do: Application
        def other, do: MyApp.Application
        def start, do: MyApp.Application.start(:normal, [])
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report the name of a module defined in a nested namespace" do
      """
      defmodule MyApp do
        defmodule Application do
          use Elixir.Application
        end
      end
      """
      |> to_source_file("lib/my_app.ex")
      |> run_check(ApplicationEnvRead)
      |> refute_issues()
    end

    test "does not report references when module_references is false" do
      """
      defmodule Acme do
        defdelegate get_env(app, key, default), to: Application
        def get(opts), do: Keyword.get(opts, :application, Application)
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead, module_references: false)
      |> refute_issues()
    end

    test "still reports calls when module_references is false" do
      """
      defmodule Acme do
        def get, do: Application.get_env(:acme, :key)
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead, module_references: false)
      |> assert_issue(fn issue -> assert issue.trigger == "Application.get_env" end)
    end
  end

  describe "params" do
    test "calls replaces the default list" do
      """
      defmodule Acme do
        def a, do: Application.get_env(:acme, :key)
        def b, do: Application.fetch_env!(:acme, :key)
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead, calls: [{Application, :fetch_env!}])
      |> assert_issue(fn issue -> assert issue.trigger == "Application.fetch_env!" end)
    end

    test "hint is appended to the message" do
      """
      defmodule Acme do
        def a, do: Application.get_env(:acme, :key)
        def b(opts), do: Keyword.get(opts, :application, Application)
      end
      """
      |> to_source_file("lib/acme.ex")
      |> run_check(ApplicationEnvRead, hint: "Read it through Acme.get_env/3 instead.")
      |> assert_issues(fn issues ->
        assert length(issues) == 2
        assert Enum.all?(issues, &String.ends_with?(&1.message, " Read it through Acme.get_env/3 instead."))
      end)
    end

    test "does not report a file listed in allowed_files" do
      """
      defmodule Acme do
        def a, do: Application.get_env(:acme, :key)
        def b(opts), do: Keyword.get(opts, :application, Application)
      end
      """
      |> to_source_file("lib/acme/config.ex")
      |> run_check(ApplicationEnvRead, allowed_files: [{"acme/config.ex", "The config reader itself."}])
      |> refute_issues()
    end

    test "matches allowed_files on whole segments" do
      """
      defmodule Acme do
        def a, do: Application.get_env(:acme, :key)
      end
      """
      |> to_source_file("lib/myconfig.ex")
      |> run_check(ApplicationEnvRead, allowed_files: [{"config.ex", "The config reader itself."}])
      |> assert_issue()
    end

    test "reports every file by default" do
      """
      defmodule Acme do
        def a, do: Application.get_env(:acme, :key)
      end
      """
      |> to_source_file("config/runtime.exs")
      |> run_check(ApplicationEnvRead)
      |> assert_issue()
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
          source_file = to_source_file("Application.get_env(:acme, :key)", "lib/acme.ex")
          ApplicationEnvRead.run(source_file, allowed_files: [entry])
        end
      end
    end
  end
end
