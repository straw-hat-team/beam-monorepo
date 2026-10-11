defmodule Trogon.Test.MixProject do
  use Mix.Project

  @app :trogon_test
  @version "0.0.1"
  @elixir_version "~> 1.18"
  @source_url "https://github.com/straw-hat-team/beam-monorepo"

  def project do
    [
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      name: "Trogon.Test",
      description: "Shared ExUnit toolkit for isolated, async-safe tests",
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
      {:mox, "~> 1.2"},
      {:telemetry, "~> 1.0", optional: true},
      {:uniq, "~> 0.6", optional: true},

      # Tools
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
        "README.md"
      ],
      groups_for_modules: [
        Helpers: [Trogon.Test, ~r/^Trogon\.Test\.Test/],
        Mocks: [~r/^Trogon\.Test\.Mock/],
        Formatters: [Trogon.Test.AIFormatter],
        Behaviours: [~r/^Trogon\.Test\.Behaviour\./]
      ],
      groups_for_extras: [
        "How-to": ~r/docs\/how-to\/.?/,
        Explanations: ~r/docs\/explanations\/.?/,
        References: ~r/docs\/references\/.?/
      ]
    ]
  end
end
