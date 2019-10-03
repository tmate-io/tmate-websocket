defmodule Tmate.Mixfile do
  use Mix.Project

  def project do
    [app: :tmate,
     version: "0.1.1",
     elixir: "~> 1.9",
     elixirc_paths: ["lib"],
     compilers: Mix.compilers,
     deps: deps(),
     # dialyzer: [paths: ~w(tmate ranch) |> Enum.map(fn(x) -> "_build/dev/lib/#{x}/ebin" end)]
     ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    case Mix.env do
      :test -> [mod: {ExUnit, []}, applications: [:logger]]
      _ ->     [mod: {Tmate, []},  applications: [:logger, :ranch, :cowboy,
                                   :plug, :plug_cowboy, :uuid, :message_pack,
                                   :quantile_estimator, :jason, :httpoison]]
    end
  end

  # Specifies your project dependencies
  #
  # Type `mix help deps` for examples and options
  defp deps do
    [
      {:ranch, "~> 1.0"},
      {:cowboy, "~> 2.0"},
      {:plug, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:uuid, "~> 1.1" },
      {:jason, ">= 0.0.0"},
      {:httpoison, ">= 0.0.0"},
      {:quantile_estimator, github: "nviennot/quantile_estimator"},
      {:message_pack, github: "nviennot/msgpack-elixir"},
      {:distillery, "~> 2.1"},
    ]
  end
end
