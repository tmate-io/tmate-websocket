defmodule Tmate.Mixfile do
  use Mix.Project

  def project do
    [app: :tmate,
     version: "0.0.19",
     elixir: "~> 1.1",
     elixirc_paths: ["lib"],
     compilers: Mix.compilers,
     deps: deps,
     # dialyzer: [paths: ~w(tmate ranch) |> Enum.map(fn(x) -> "_build/dev/lib/#{x}/ebin" end)]
     ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    # XXX Probably very gross, not sure how not to start listening on ports and all.
    case Mix.env do
      :test -> [mod: {ExUnit, []}, applications: [:logger]]
      _ ->     [mod: {Tmate, []},  applications: [:logger, :ranch, :cowboy,
                                   :rollbax, :plug, :uuid, :message_pack, :edeliver,
                                   :ex_statsd, :quantile_estimator]]
    end
  end

  # Specifies your project dependencies
  #
  # Type `mix help deps` for examples and options
  defp deps do
    [
      # {:ranch, "~> 1.0"},
      {:cowboy, "~> 1.0"},
      {:plug, "~> 1.0"},
      {:uuid, "~> 1.1" },
      {:rollbax, ">= 0.0.0"},
      {:exrm, ">= 0.0.0"},
      {:edeliver, ">= 0.0.0"},
      {:ex_statsd, ">= 0.0.0"},
      {:quantile_estimator, github: "nviennot/quantile_estimator"},
      {:message_pack, github: "nviennot/msgpack-elixir"}
    ]
  end
end
