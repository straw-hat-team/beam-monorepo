defmodule BeamMonorepoUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      name: "BeamMonorepo",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: test_coverage(),
      dialyzer: dialyzer()
    ]
  end

  def cli do
    [preferred_envs: preferred_cli_env()]
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
      plt_add_apps: [:mix],
      plt_local_path: "priv/plts"
    ]
  end

  defp deps do
    [
      # Override to resolve conflict between excoveralls (only: [:test, :dev])
      # and polymorphic_embed (needs it in all environments)
      {:jason, "~> 1.4"}
    ]
  end
end
