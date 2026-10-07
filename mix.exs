defmodule Cuckoding.MixProject do
  use Mix.Project

  def project do
    [
      app: :cuckoding,
      version: "0.1.0",
      elixir: "~> 1.20.3",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application, do: [mod: {Cuckoding.Application, []}, extra_applications: [:logger, :crypto]]
  def cli, do: [preferred_envs: [quality: :test]]

  defp deps do
    [
      {:phoenix, "~> 1.8.13"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.24"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, "~> 0.1", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.8"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind cuckoding", "esbuild cuckoding"],
      "assets.deploy": ["tailwind cuckoding --minify", "esbuild cuckoding --minify", "phx.digest"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "sobelow --config",
        "deps.audit"
      ]
    ]
  end
end
