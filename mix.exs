defmodule DepMulti.MixProject do
  use Mix.Project

  @version "0.1.3"
  @url "https://github.com/annkissam/dep_multi"
  @maintainers [
    "Eric Sullivan"
  ]

  def project do
    [
      app: :dep_multi,
      version: @version,
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Task.async with depenencies / Ecto.Multi syntax",
      package: package(),
      source_url: @url,
      homepage_url: @url,
      docs: docs(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {DepMulti.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  def docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      name: :dep_multi,
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{github: @url},
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG.md"]
    ]
  end

  defp aliases do
    [publish: ["hex.publish", &git_tag/1]]
  end

  defp git_tag(_args) do
    System.cmd("git", ["tag", "v" <> Mix.Project.config()[:version]])
    System.cmd("git", ["push", "--tags"])
  end
end
