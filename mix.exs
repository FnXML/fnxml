defmodule FnXML.MixProject do
  use Mix.Project

  @version "0.2.0"

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def project do
    [
      app: :fnxml,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Test coverage
      test_coverage: [tool: ExCoveralls],

      # Docs
      name: "FnXML",
      source_url: "https://github.com/yourname/fnxml",
      docs: docs(),
      description: description(),
      package: package()
    ]
  end

  defp description do
    "High-performance streaming XML parser for Elixir."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourname/fnxml"},
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*)
    ]
  end

  defp docs do
    [
      main: "FnXML",
      extras: ["README.md", "quick_start_guide.md", "usage-rules.md"],
      groups_for_modules: [
        Core: [FnXML, FnXML.Parser, FnXML.Transform.Stream],
        "DOM API": [
          FnXML.DOM,
          FnXML.DOM.Document,
          FnXML.DOM.Element,
          FnXML.DOM.Builder,
          FnXML.DOM.Serializer
        ],
        "SAX API": [FnXML.SAX, FnXML.SAX.Handler],
        "StAX API": [FnXML.StAX, FnXML.StAX.Reader, FnXML.StAX.Writer],
        Security: [
          FnXML.Security.C14N,
          FnXML.Security.Signature,
          FnXML.Security.Encryption,
          FnXML.Security.Algorithms,
          FnXML.Security.Namespaces
        ],
        Namespaces: [
          FnXML.Transform.Namespaces,
          FnXML.Transform.Namespaces.Context,
          FnXML.Transform.Namespaces.QName,
          FnXML.Transform.Namespaces.Resolver,
          FnXML.Validate.Namespaces
        ],
        DTD: [FnXML.DTD, FnXML.DTD.Model, FnXML.DTD.Parser],
        Utilities: [FnXML.Element, FnXML.Transform.Stream.SimpleForm]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :xmerl, :public_key, :crypto]]
  end

  defp deps do
    [
      {:mix_test_watch, "~> 1.2", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:nimble_parsec, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:benchee, "~> 1.3", only: :dev},
      {:benchee_html, "~> 1.0", only: :dev},
      {:saxy, "~> 1.5", only: :dev},
      {:erlsom, "~> 1.5", only: :dev},
      {:nx, "~> 0.7", only: :dev}
    ]
  end
end
