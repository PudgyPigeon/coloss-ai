defmodule Wire.MixProject do
  use Mix.Project

  def project do
    [
      app: :wire,
      version: "0.0.1",
      elixir: "~> 1.19",
      # This equality operator sets key:val to 'True" atom, meaning it'll crash the VM on failure - :false if dev or staging
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :os_mon], # remove some addons if you dont need the metrics in the dashboard
      mod: {Wire.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8.7"},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:libcluster, "~> 3.3"},
      {:plug_cowboy, "~> 2.8.0"},
      {:jason, "~> 1.4.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end
end
