defmodule Trogon.Credo.Check.ExUnit.ApplicationEnvMutation do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      calls: [
        {Application, :put_env},
        {Application, :put_all_env},
        {Application, :delete_env},
        {:application, :set_env},
        {:application, :unset_env}
      ],
      hint: nil
    ],
    explanations: [
      check: """
      `Application.put_env/3,4` writes to the application controller's global, node-wide
      table, the same one every process reads from with `Application.get_env/2,3`. A test
      that calls it changes what every other test concurrently running reads, not only its
      own, so it cannot run `async: true`, and the `on_exit` that restores the previous
      value races whatever else writes or reads the same key while it runs.

      A function that depends on config takes it as an argument instead of reaching for
      `Application.get_env/2,3` itself, and a test that drives such a function passes the
      value it wants, nothing global touched. A function that cannot take the config as an
      argument, one behind a boundary the project does not own, reads it through a facade
      the project compiles in: `Application` in every environment but test, and a mock a
      test can stub per process in test, so one test overrides one key without writing to
      the table every other test reads too. `trogon_test` ships that mock, so the
      project writes only the facade:

          # preferred
          defmodule Acme do
            @application Application.compile_env(:acme, [__MODULE__, :application], Application)

            defdelegate get_env(app, key, default \\\\ nil), to: @application
          end

          defmodule Acme.Billing do
            def tax_rate do
              Acme.get_env(:acme, :tax_rate, 0.0)
            end
          end

          # config/test.exs
          config :acme, Acme, application: Trogon.Test.MockApplication

          defmodule Acme.BillingTest do
            use ExUnit.Case, async: true
            use Trogon.Test

            test "charges the configured tax rate" do
              TestApplication.expect_get_env(times: 1, returns: 0.07)

              assert Acme.Billing.tax_rate() == 0.07
              TestApplication.assert_received_get_env(:acme, :tax_rate)
            end
          end

          # NOT preferred
          defmodule Acme.BillingTest do
            use ExUnit.Case

            setup do
              previous = Application.get_env(:acme, :tax_rate)
              Application.put_env(:acme, :tax_rate, 0.07)
              on_exit(fn -> Application.put_env(:acme, :tax_rate, previous) end)
            end

            test "charges the configured tax rate" do
              assert Acme.Billing.tax_rate() == 0.07
            end
          end

      This check runs `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` with a default
      list covering `Application.put_env/3,4`, `Application.put_all_env/1,2`,
      `Application.delete_env/2,3`, and their Erlang counterparts,
      `:application.set_env/1,2,3,4` and `:application.unset_env/2,3`, the way
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` reports every call to them:
      qualified, through an alias, piped, captured, or written against the Erlang module
      directly.

      Only a test file is scoped: a filename ending in `_test.exs`, or one under a
      `test/support` directory anywhere in its path. A lib file is never reported, since
      this check is about keeping tests isolated from each other, and a lib file that
      writes config, a release's start phase for instance, is a different decision with
      its own trade-offs. `Application.get_env/2,3` is left alone
      too, since reading config is never what makes a test unsafe to run `async: true`,
      only writing it is.
      """,
      params: [
        calls: """
        The calls this check forbids in a test file, given in the form
        `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` accepts for its own `calls:`
        param, without messages. Defaults to a list covering `Application.put_env`,
        `Application.put_all_env`, `Application.delete_env`, and their Erlang
        counterparts, `:application.set_env` and `:application.unset_env`. A project with
        its own source of global mutation, a wrapper around one of these for instance,
        replaces the default with its own list.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can name its own stubbable seam, `"Read it through Acme.Config instead."`
        for instance. Skipped when set to `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall
  alias Trogon.Credo.CheckDelegate

  @message "Application env is global to the node; a test that writes it here changes " <>
             "config for every test running at the same time. Pass the config in as an " <>
             "argument, or read it through a seam the test can stub, instead of mutating " <>
             "it directly."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    if test_file?(source_file.filename) do
      run_on_test_file(source_file, params)
    else
      []
    end
  end

  defp run_on_test_file(source_file, params) do
    calls = params |> Params.get(:calls, __MODULE__) |> List.wrap()

    CheckDelegate.run(source_file, params, __MODULE__, ForbiddenFunctionCall,
      calls: Enum.map(calls, &forbidden_call/1),
      except: [],
      hint: Params.get(params, :hint, __MODULE__)
    )
  end

  # A test file is the only place this check scopes, since a test is the only
  # caller that runs concurrently with every other test writing the same global
  # table, and a file under `test/support` exists to build fixtures for tests.
  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs") or test_support_file?(filename)
  end

  defp test_support_file?(filename) do
    filename |> Path.split() |> under_test_support?()
  end

  defp under_test_support?(["test", "support" | _rest]), do: true
  defp under_test_support?([_segment | rest]), do: under_test_support?(rest)
  defp under_test_support?([]), do: false

  defp forbidden_call({module, function, arity}) when is_atom(function) and is_integer(arity) do
    {{module, function, arity}, @message}
  end

  defp forbidden_call({module, function}) when is_atom(function), do: {{module, function}, @message}
  defp forbidden_call(module), do: {module, @message}
end
