defmodule HawkEye.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/EssenceOfChaos/hawk_eye"

  def project do
    [
      app: :hawk_eye,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Heartbeat monitoring for Oban jobs and scheduled tasks with HawkEye: " <>
          "get alerted when a job fails or silently stops running.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url:
        "https://hawkeye.observer/elixir?utm_medium=hex&utm_source=hawk_eye&utm_campaign=elixir"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :public_key],
      mod: {HawkEye.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "HawkEye" =>
          "https://hawkeye.observer/elixir?utm_medium=hex&utm_source=hawk_eye&utm_campaign=elixir",
        "Create a free HawkEye account" =>
          "https://hawkeye.observer/register?utm_medium=hex&utm_source=hawk_eye&utm_campaign=elixir",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", LICENSE: [title: "License"]]
    ]
  end
end
