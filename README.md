# LiveSelect

[![Hex](https://img.shields.io/hexpm/v/live_select.svg)](https://hex.pm/packages/live_select)
[![Hexdocs](https://img.shields.io/badge/-docs-green)](https://hexdocs.pm/live_select)

LiveSelect is a dynamic selection field for Phoenix LiveView. Your LiveView retrieves options as the user types, and LiveSelect renders the dropdown and submits the selection through the form.

- Select one value with `:single`, several values with `:tags`, or several values while keeping the dropdown open with `:quick_tags`.
- Configure search timing, selection limits, disabled options, and user-defined values.
- Use Tailwind CSS or daisyUI styles, or supply your own classes with `style={:none}`.
- Customise option labels, tags, and clear buttons through slots.

This repository contains the dependency and its source JavaScript hook. It does not include a demo application, test dependencies, a JavaScript build step, or a server to start.

## Installation

To use this checkout before its changes are published, add a local path dependency. Replace the example path with the checkout's location:

```elixir
{:live_select, ">= 1.7.5", path: "../live_select"}
```

To consume the fork's source from GitHub after the changes are pushed:

```elixir
{:live_select, ">= 1.7.5", github: "RisPNG/live_select"}
```

The upstream Hex release remains available, but it does not include this fork's unreleased changes:

```elixir
{:live_select, ">= 1.7.5"}
```

Run the dependency command from your application:

```sh
mise exec -- mix deps.get
```

The Hex version requirement permits newer releases. Your application's `mix.lock` selects exact Hex versions or Git commits, so use `mise exec -- mix deps.update live_select` when you intend to update it. A path dependency uses the current checkout directly.

Import the component in your application's HTML helpers, or call it as `<LiveSelect.live_select />`:

```elixir
import LiveSelect, only: [live_select: 1]
```

## JavaScript hook

Add the hook to the `LiveSocket` configuration in your application's `assets/js/app.js`:

```javascript
import LiveSelect from "live_select"

const hooks = {
  ...LiveSelect,
  MyHook
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks
})
```

If you have no other hooks, pass `hooks: LiveSelect` directly. LiveSelect ships the ESM source in its Hex package, so the consuming application's asset builder bundles it with the other hooks.

Replace direct imports of `priv/static/live_select.min.js` with the package import above. The prebuilt minified file is no longer included.

Phoenix applications using esbuild's dependency paths can resolve this import directly. If your asset builder resolves packages through npm, add the Hex dependency as a local package in `assets/package.json`:

```json
{
  "dependencies": {
    "live_select": "file:../deps/live_select"
  }
}
```

Use `file:../../../deps/live_select` when the assets directory is inside an umbrella application's `apps/my_app/assets`. Run `mise exec -- npm install` in the assets directory after adding the package, and refresh the local package when updating the Hex dependency.

## Usage

Render LiveSelect inside a form:

```heex
<.form for={@form} phx-change="change">
  <.live_select field={@form[:city_search]} />
</.form>
```

If the component belongs to a LiveComponent, pass `phx-target={@myself}` so search events reach that component:

```heex
<.live_select field={@form[:city_search]} phx-target={@myself} />
```

Handle `live_select_change` in the target LiveView or LiveComponent. The event provides the search text, component ID, and form field ID:

```elixir
@impl true
def handle_event("live_select_change", %{"text" => text, "id" => id}, socket) do
  options = City.search(text)

  send_update(LiveSelect.Component, id: id, options: options)

  {:noreply, socket}
end
```

`City.search/1` is your application's search function. It can return labels and values such as `[{"New York City", "NYC"}, {"New Kingston", "NK"}]`. Selecting an option triggers the form's normal change event:

```elixir
@impl true
def handle_event("change", %{"my_form" => %{"city_search" => city}}, socket) do
  {:noreply, assign(socket, selected_city: city)}
end
```

Composite values, such as maps and lists, are submitted as JSON. Use `LiveSelect.decode/1` to decode them before processing form parameters. LiveSelect uses the JSON library configured by Phoenix. Applications using Elixir 1.18 or later can configure `config :phoenix, :json_library, JSON`, or provide the Jason library used by Phoenix's default configuration. Ecto support preserves form values from schemas, associations, and embeds.

See the [module documentation](https://hexdocs.pm/live_select/LiveSelect.html) for the full API and the [cheatsheet](cheatsheet.cheatmd) for common configurations.

## Styling

Use `style={:tailwind}` for the default Tailwind utilities, `style={:daisyui}` for daisyUI components, or `style={:none}` for your own CSS. Tailwind CSS and daisyUI belong to the consuming application's asset setup.

For Tailwind CSS 4, register the dependency's source directory in `assets/css/app.css`:

```css
@import "tailwindcss";
@source "../../deps/live_select/lib";
```

Use `@source "../../../../deps/live_select/lib";` for an umbrella application's `apps/my_app/assets/css/app.css`. Paths are relative to the stylesheet. Registering the directory covers the Elixir styles and HEEx template, as described in [Tailwind's source detection documentation](https://tailwindcss.com/docs/detecting-classes-in-source-files).

For daisyUI 5, also enable its plugin in your application's CSS, following the [daisyUI installation guide](https://daisyui.com/docs/install/):

```css
@plugin "daisyui";
```

See the [styling guide](styling.md) for class overrides, supported elements, and Tailwind CSS 3 configuration.

## Maintaining the dependency

`mise.toml` selects `latest` for Elixir, Erlang/OTP, Node.js, npm, and Rebar, while `.tool-versions` records a fixed snapshot of their current releases. npm is selected separately from the version bundled with Node.js, and Mix uses the managed Rebar executable. Install the tools and Hex, then fetch dependencies, compile, check formatting, and inspect the Hex package with:

```sh
mise install
mise exec -- mix local.hex --force
mise exec -- mix deps.get
mise exec -- mix compile --warnings-as-errors
mise exec -- mix format --check-formatted
mise exec -- mix hex.build
```

Use `mise upgrade` to fetch newer tool releases. Update all locked dependencies with `mise exec -- mix deps.update --all` when adopting newer releases. Requirements use `>=`, while `mix.lock` records the versions used for local verification. This permits future releases but cannot guarantee compatibility with changes they introduce.
