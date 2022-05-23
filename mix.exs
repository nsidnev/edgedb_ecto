defmodule EdgedbEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :edgedb_ecto,
      version: "0.0.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # we need support for passing maps which is not released yet
      {:edgedb, git: "https://github.com/nsidnev/edgedb-elixir"},
      {:ecto, "~> 3.7"}
    ]
  end
end
