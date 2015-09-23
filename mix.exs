defmodule Tmate.Mixfile do
  use Mix.Project

  def project do
    [app: :tmate,
     version: "0.0.1",
     elixir: "~> 1.0",
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
    [mod: {Tmate, []},
     applications: [:logger, :ranch, :cowboy]]
  end

  # Specifies your project dependencies
  #
  # Type `mix help deps` for examples and options
  defp deps do
    [
      {:ranch, "~> 1.1.0"},
      {:cowboy, "~> 1.0.3"},
      {:poison, []},
      {:message_pack, "~> 0.2.0"},
    ]
  end
end
