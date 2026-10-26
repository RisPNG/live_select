defmodule LiveSelect.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_select,
      version: "1.7.5",
      elixir: ">= 1.15.0",
      description: "Dynamic (multi)selection field for LiveView",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:phoenix_live_view, ">= 1.2.13"},
        {:phoenix_html, ">= 4.3.0"},
        {:phoenix, ">= 1.8.16"},
        {:ecto, ">= 3.14.2"},
        {:lazy_html, ">= 0.1.0", only: :test}
      ],
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/RisPNG/live_select"},
        files:
          ~w(mix.exs lib assets/js/live_select.js assets/css/live_select.css package.json LICENSE README.md styling.md cheatsheet.cheatmd CHANGELOG.md)
      ],
      source_url: "https://github.com/RisPNG/live_select",
      name: "LiveSelect"
    ]
  end
end
