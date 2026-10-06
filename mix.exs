defmodule PepePlugins.MixProject do
  use Mix.Project

  # This project only exists to test the plugins in this repository. A plugin is a plain `.exs`
  # file that Pepe compiles when it is installed; none of this is shipped with it. The Pepe
  # runtime is not a dependency (it pulls in a lot), so the few modules a plugin leans on are
  # stood in for under test/support, matching Pepe's own contract.
  def project do
    [
      app: :pepe_plugins,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: false,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16", only: :test},
      {:bandit, "~> 1.5", only: :test}
    ]
  end
end
