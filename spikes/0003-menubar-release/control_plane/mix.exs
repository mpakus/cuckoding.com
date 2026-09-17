defmodule CuckodingShellSpike.MixProject do
  use Mix.Project

  def project do
    [
      app: :cuckoding_shell_spike,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [mod: {CuckodingShellSpike.Application, []}, extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:phoenix, "1.8.13"},
      {:phoenix_live_view, "1.2.11"},
      {:bandit, "1.12.5"},
      {:jason, "1.4.5"}
    ]
  end
end
