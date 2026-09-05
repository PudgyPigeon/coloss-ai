defmodule Wire.MixProject do
  @moduledoc false

  use Mix.Project

  def project do
    [
      app: :wire,
      version: "0.0.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :os_mon],
      mod: {Wire.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:libcluster, "~> 3.3"},
      {:plug_cowboy, "~> 2.8.0"},
      {:jason, "~> 1.4.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end
end
