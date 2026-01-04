defmodule Nexus.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/manav03panchal/nexus"

  def project do
    [
      app: :nexus,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      releases: releases(),
      aliases: aliases(),

      # Test configuration
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [
          :error_handling,
          :missing_return,
          :underspecs,
          :unknown
        ]
      ],

      # Docs
      name: "Nexus",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh, :public_key],
      mod: {Nexus.Application, []}
    ]
  end

  defp escript do
    [
      main_module: Nexus.CLI,
      name: "nexus"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:optimus, "~> 0.5"},
      {:owl, "~> 0.12"},
      {:sshkit, "~> 0.3"},
      {:nimble_pool, "~> 1.1"},
      {:libgraph, "~> 0.16"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:fuse, "~> 2.5"},
      {:hammer, "~> 6.2"},
      {:burrito, "~> 1.0"},

      # Web Dashboard
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:heroicons, "~> 0.5",
       github: "tailwindlabs/heroicons", sparse: "optimized", app: false, compile: false, depth: 1},

      # Dev & Test
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: [:dev, :test]},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile", "assets.setup"],
      lint: ["format --check-formatted", "credo --strict", "sobelow --config"],
      "test.unit": ["test --only unit"],
      "test.integration": ["test --only integration"],
      "test.property": ["test --only property"],
      "test.all": ["test --include integration --include property"],
      quality: ["format", "credo --strict", "dialyzer", "sobelow --config"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind nexus_web", "esbuild nexus_web"],
      "assets.deploy": [
        "tailwind nexus_web --minify",
        "esbuild nexus_web --minify",
        "phx.digest"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp releases do
    [
      nexus: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_aarch64: [os: :linux, cpu: :aarch64],
            darwin_x86_64: [os: :darwin, cpu: :x86_64],
            darwin_aarch64: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end
end
