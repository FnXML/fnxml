defmodule FnXML.MixProject do
  use Mix.Project

  def project do
    [
      app: :fnxml,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mix_test_watch, "~> 1.2", only: :dev, runtime: false},
      {:nimble_parsec, "~> 1.4"},
      # Benchmarking
      {:benchee, "~> 1.3", only: :dev},
      {:benchee_html, "~> 1.0", only: :dev},
      {:saxy, "~> 1.5", only: :dev},
      {:erlsom, "~> 1.5", only: :dev},
      {:nx, "~> 0.7", only: :dev},
      {:zigler, "~> 0.13", runtime: false}
    ]
  end
end
