defmodule Trogon.Dispatcher.MixProject do
  use Mix.Project

  @app :trogon_dispatcher
  @version "0.1.0"
  @elixir_version "~> 1.14"
  @source_url "https://github.com/straw-hat-team/beam-monorepo"

  def project do
    [
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      name: "Trogon.Dispatcher",
      description: "In-process command and query dispatcher with composable middleware and telemetry",
      app: @app,
      version: @version,
      elixir: @elixir_version,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: test_coverage(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def cli do
    [preferred_envs: preferred_cli_env()]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:telemetry, "~> 1.0"},

      # Optional OpenTelemetry integration
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:opentelemetry_telemetry, "~> 1.0", optional: true},
      {:nimble_options, "~> 1.0", optional: true},
      {:opentelemetry, "~> 1.0", only: [:test]},

      # Tools
      {:mox, ">= 0.0.0", only: [:test]},
      {:dialyxir, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, ">= 0.0.0", only: [:test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["test --trace"]
    ]
  end

  defp test_coverage do
    [tool: ExCoveralls]
  end

  defp preferred_cli_env do
    [
      "coveralls.html": :test,
      "coveralls.json": :test,
      coveralls: :test
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts"
    ]
  end

  defp package do
    [
      name: @app,
      files: [
        ".formatter.exs",
        "docs",
        "lib",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      maintainers: ["Yordis Prieto"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      homepage_url: @source_url,
      source_url_pattern: "#{@source_url}/blob/#{@app}@v#{@version}/apps/#{@app}/%{path}#L%{line}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/tutorials/build-an-accounts-dispatcher.md",
        "docs/how-to/compose-dispatchers.md",
        "docs/how-to/write-middleware.md",
        "docs/how-to/test-with-mox.md",
        "docs/how-to/observe-with-telemetry.md",
        "docs/how-to/trace-with-opentelemetry.md",
        "docs/explanations/why-wrapping-middleware.md",
        "docs/explanations/handlers-and-context.md",
        "docs/explanations/compile-time-model.md",
        "docs/explanations/prior-art.md"
      ],
      groups_for_extras: [
        Tutorials: ~r/docs\/tutorials\/.?/,
        "How-to": ~r/docs\/how-to\/.?/,
        Explanations: ~r/docs\/explanations\/.?/
      ]
    ]
  end
end
