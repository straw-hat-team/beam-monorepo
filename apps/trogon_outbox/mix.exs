defmodule Trogon.Outbox.MixProject do
  use Mix.Project

  @app :trogon_outbox
  @version "0.1.0"
  @elixir_version "~> 1.18"
  @source_url "https://github.com/straw-hat-team/beam-monorepo"
  @oban_pro_dir ".oban_pro"

  def project do
    [
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: lockfile(),
      name: "Trogon.Outbox",
      description: "Transactional outbox pattern for Elixir",
      app: @app,
      version: @version,
      elixir: @elixir_version,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: test_paths(),
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

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19 or ~> 1.0"},
      {:oban, "~> 2.24", only: :test},
      {:amqp, "~> 4.3", optional: true},

      # Tools
      {:dialyxir, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, ">= 0.0.0", only: [:test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false}
    ] ++ oban_pro_deps()
  end

  defp oban_pro_deps do
    if oban_pro?(), do: [{:oban_pro, "~> 1.8", repo: "oban", only: :test}], else: []
  end

  defp elixirc_paths(:test) do
    if oban_pro?(), do: ["lib", "test/support", "test_pro/support"], else: ["lib", "test/support"]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp test_paths do
    if oban_pro?(), do: ["test", "test_pro"], else: ["test"]
  end

  defp oban_pro?, do: System.get_env("TROGON_OUTBOX_OBAN_PRO") == "true"

  defp lockfile do
    if oban_pro?() do
      lockfile = Path.join([__DIR__, @oban_pro_dir, "mix.lock"])

      unless File.exists?(lockfile) do
        File.mkdir_p!(Path.dirname(lockfile))
        File.cp!(Path.join(__DIR__, "../../mix.lock"), lockfile)
      end

      lockfile
    else
      "../../mix.lock"
    end
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
      "coveralls.github": :test,
      coveralls: :test
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      ignore_warnings: ".dialyzer_ignore.exs"
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
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/how-to/use-the-outbox.md",
        "docs/explanations/ordering-gaps.md",
        "docs/explanations/oban-as-an-outbox-relay.md",
        "docs/explanations/postgres-outbox-design.md"
      ],
      groups_for_extras: [
        "How-to": ~r/docs\/how-to\/.?/,
        Explanations: ~r/docs\/explanations\/.?/,
        References: ~r/docs\/references\/.?/
      ]
    ]
  end
end
