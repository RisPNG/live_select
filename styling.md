# Styling

LiveSelect supports `:tailwind`, `:daisyui`, and `:none` through the `style` attribute. The default is `:tailwind`. The built-in styles are defined together in `LiveSelect.Component`, and the consuming application supplies Tailwind CSS or daisyUI through its own asset build.

## Tailwind CSS 4

Register the dependency source directory in the application's `assets/css/app.css`. This includes both the Elixir class definitions and the HEEx template:

```css
@import "tailwindcss";
@source "../../deps/live_select/lib";
```

For an umbrella application's `apps/my_app/assets/css/app.css`, use:

```css
@source "../../../../deps/live_select/lib";
```

Paths are relative to the stylesheet. Tailwind ignores dependency directories during automatic detection, so register this source explicitly. See [Tailwind's source detection documentation](https://tailwindcss.com/docs/detecting-classes-in-source-files).

## daisyUI 5

Enable daisyUI in the consuming application's CSS, alongside Tailwind and the source directive:

```css
@import "tailwindcss";
@plugin "daisyui";
@source "../../deps/live_select/lib";
```

Then render `<.live_select field={@form[:city]} style={:daisyui} />`. The active daisyUI theme supplies the colours. Follow the [daisyUI installation guide](https://daisyui.com/docs/install/) for the application's asset setup.

## Tailwind CSS 3

Applications still using Tailwind CSS 3 can register both source file types in `assets/tailwind.config.js`:

```javascript
module.exports = {
  content: [
    "../deps/live_select/lib/**/*.{ex,heex}"
  ]
}
```

Use `../../../deps/live_select/lib/**/*.{ex,heex}` in an umbrella application's `apps/my_app/assets/tailwind.config.js`. Keep your application's existing content paths alongside this entry.

## Supported elements

The class options accept a string or list of strings. `{element}_class` replaces the default classes, while `{element}_extra_class` extends them. Passing both for the same element raises an error. Extra classes require a built-in style, so use class overrides when `style={:none}`.

| Element | Purpose | Class override | Class extension |
| --- | --- | --- | --- |
| `container` | The outer component | `container_class` | `container_extra_class` |
| `text_input` | The search input | `text_input_class` | `text_input_extra_class` |
| `text_input_selected` | Additional input classes when the selection is nonempty | `text_input_selected_class` | |
| `dropdown` | The options list | `dropdown_class` | `dropdown_extra_class` |
| `option` | Each dropdown option | `option_class` | `option_extra_class` |
| `active_option` | The option highlighted by keyboard navigation | `active_option_class` | |
| `selected_option` | An option already in the selection | `selected_option_class` | |
| `available_option` | An option that can be selected | `available_option_class` | |
| `unavailable_option` | A disabled option, or an option unavailable because the selection limit was reached | `unavailable_option_class` | |
| `clear_button` | The single-selection clear button | `clear_button_class` | `clear_button_extra_class` |
| `tag` | Each selected tag | `tag_class` | `tag_extra_class` |
| `tags_container` | The container of selected tags | `tags_container_class` | `tags_container_extra_class` |
| `clear_tag_button` | The button that removes a tag | `clear_tag_button_class` | `clear_tag_button_extra_class` |

## Default classes

These classes come from the component's central style definitions. The template separately applies native CSS for the search-input grid and clear-button sizing, so these basic controls also work without Tailwind.

| Element | daisyUI classes | Tailwind classes |
| --- | --- | --- |
| `active_option` | `menu-active` | `text-white bg-gray-600` |
| `available_option` | `cursor-pointer` | `cursor-pointer hover:bg-gray-400 rounded` |
| `unavailable_option` | `menu-disabled` | `text-gray-400` |
| `clear_button` | `cursor-pointer` | `cursor-pointer` |
| `clear_tag_button` | `cursor-pointer` | `cursor-pointer` |
| `container` | `dropdown dropdown-open` | `h-full text-black relative` |
| `dropdown` | `dropdown-content z-[1] menu menu-sm shadow rounded-box bg-base-200 p-1 w-full` | `absolute rounded-md shadow z-50 bg-gray-100 inset-x-0 top-full` |
| `option` | | `rounded px-4 py-1` |
| `selected_option` | `cursor-pointer font-bold` | `cursor-pointer font-bold hover:bg-gray-400 rounded` |
| `text_input` | `input w-full pr-6` | `rounded-md w-full disabled:bg-gray-100 disabled:placeholder:text-gray-400 disabled:text-gray-400 pr-6` |
| `text_input_selected` | `input-primary` | `border-gray-600 text-gray-600` |
| `tags_container` | `flex flex-wrap gap-1 p-1` | `flex flex-wrap gap-1 p-1` |
| `tag` | `p-1.5 text-sm badge badge-primary grid grid-cols-[minmax(0,1fr)_auto] items-center` | `p-1 text-sm rounded-lg bg-blue-400 grid grid-cols-[minmax(0,1fr)_auto] items-center` |

## Override and extend classes

Use your application's existing theme classes when changing colours. For example, a shared `search-option-active` class can provide the active option's colours, while an extra class removes rounded option corners:

```heex
<.live_select
  field={@form[:city]}
  mode={:tags}
  active_option_class="search-option-active"
  option_extra_class="!rounded"
/>
```

The leading `!` removes a class from LiveSelect's defaults. If an element starts with `rounded-lg px-4`, an extra-class value of `!rounded-lg py-1` produces `px-4 py-1`. This removal syntax belongs to LiveSelect's class options.

For full control, use `style={:none}` and supply the classes your application owns:

```heex
<.live_select
  field={@form[:city]}
  style={:none}
  container_class="search-select"
  text_input_class="search-input"
  dropdown_class="search-options"
  option_class="search-option"
  active_option_class="search-option-active"
/>
```

## Clear buttons

LiveSelect positions and sizes clear buttons through native CSS in its template. The search input and its clear button share one grid cell, with the button aligned to the right. Clear buttons have a minimum size of `1.25rem`. Use the `:clear_button` slot to replace their content. Set `no_basic_styles_for_clear_buttons={true}` when the application's classes should control their size and positioning as well.

The default clear control is small, so a text label such as "Clear" needs custom button styles. Keep those styles in the same shared theme layer as the other form controls.

The [cheatsheet](cheatsheet.cheatmd) includes examples for labels, validation errors, dropdown placement, and scrollable options.
