defmodule Mutineer.MixProject do
  use Mix.Project

  def project do
    [
      app: :mutineer,
      version: "0.1.1",
      elixir: "~> 1.14",
      description: "A chaos engineering library for Elixir that makes functions return errors based on configurable failure rates.",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: [
        name: :mutineer,
        licenses: ["GPL-3.0"],
        links: %{"GitHub" => "https://github.com/rum-and-code/mutineer"},
        maintainers: ["rum-and-code", "hyftar"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
