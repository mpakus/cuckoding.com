defmodule Cuckoding.MixProject do
  use Mix.Project

  def project do
    [
      app: :cuckoding,
      version: "0.1.0",
      elixir: "== 1.19.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Cuckoding.Application, []},
      extra_applications: [:crypto, :logger, :runtime_tools]
    ]
  end

  def cli do
    [preferred_envs: [quality: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix, "== 1.8.14"},
      {:phoenix_html, "== 4.3.0"},
      {:phoenix_live_reload, "== 1.7.0", only: :dev},
      {:phoenix_live_view, "== 1.2.12"},
      {:ecto_sql, "== 3.14.0"},
      {:ecto_sqlite3, "== 0.24.1"},
      {:lazy_html, "== 0.1.12", only: :test},
      {:stream_data, "== 1.4.0", only: :test},
      {:esbuild, "== 0.10.0", runtime: Mix.env() == :dev},
      {:tailwind, "== 0.5.1", runtime: Mix.env() == :dev},
      {:jason, "== 1.4.5"},
      {:yaml_elixir, "== 2.12.2"},
      {:bandit, "== 1.12.5"},
      {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
      {:sobelow, "== 0.15.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind cuckoding", "esbuild cuckoding"],
      "assets.deploy": [
        "tailwind cuckoding --minify",
        "esbuild cuckoding --minify",
        "phx.digest"
      ],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      quality: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "sobelow --config",
        "cmd mix hex.audit"
      ]
    ]
  end
end
