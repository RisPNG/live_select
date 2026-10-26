defmodule LiveSelect do
  use Phoenix.Component

  alias LiveSelect.Component

  embed_templates("live_select.html", suffix: "_template")

  @moduledoc ~S"""
  A dynamic selection field for Phoenix LiveView.

  Render `live_select/1` with a `Phoenix.HTML.FormField`. LiveSelect creates a text input for searching and hidden inputs containing the selected values. The search input's name and ID use the form field's name and ID with `_text_input` appended.

  When the user types, LiveSelect sends `live_select_change` to the parent LiveView or the configured `phx-target`. Its parameters contain `text`, the search text, `id`, the LiveSelect component ID, and `field`, the form field ID. Handle this event, retrieve matching options, and send them to `LiveSelect.Component` with `Phoenix.LiveView.send_update/3`.

  Users can navigate with the arrow keys, select with Enter, or click an option. Selecting or clearing a value triggers the form's normal change event. LiveSelect restores the current selection when the LiveView reconnects.

  ## Selection modes

  - `:single` selects one option. Set `allow_clear` to display a button that clears it.
  - `:tags` selects several options and displays removable tags above the search input.
  - `:quick_tags` selects several options while keeping the dropdown open. Selected options can also be removed through the dropdown. The dropdown closes when focus leaves the component.

  In tags and quick-tags modes, selected values are submitted as a list, like an HTML select with the `multiple` attribute. `max_selectable` limits the selection, and `0` permits any number of entries.

  Single and tags modes clear the search options after selection unless `keep_options_on_select` is set. Quick-tags mode preserves the options. In single mode, `keep_label_on_select` keeps the selected label visible while the input is focused.

  ## Options

  Use `options` for the initial options. After the first render, send changes through `Phoenix.LiveView.send_update/3`. Rerendering the parent form does not replace the component's current options.

  `options` accepts an enumerable containing:

  - Atoms, strings, or numbers, used as both the label and value.
  - Tuples, such as `{label, value}` or `{label, value, disabled}`.
  - Maps, such as `%{label: label, value: value}` or `%{value: value}`.
  - Keyword lists, such as `[label: label, value: value]` or `[value: value]`.

  Maps and keyword lists without `label` use the value as the label. An enumerable of tuples can also be supplied as a map or keyword list. For example, `%{Red: 1, Yellow: 2, Green: 3}` provides labels `:Red`, `:Yellow`, and `:Green`, with values `1`, `2`, and `3`.

  Set `disabled: true` on a map or keyword option, or use a 3-element tuple, to display an option that cannot be selected. In tags and quick-tags modes, set `sticky: true` on a map or keyword option to prevent users from removing a selected tag. Programmatic `value` updates can still replace the selection.

  Scalar values are submitted through ordinary form inputs. Composite values, such as maps and lists, are JSON-encoded. Use `decode/1` on the received parameters before passing composite values to your application's form handling code. LiveSelect uses the JSON library configured by Phoenix.

  ## Alternative selected labels

  In single mode, `selected_label` changes the text shown after selection while `label` remains the dropdown label:

  ```elixir
  %{label: "+60 Malaysia (MY)", selected_label: "+60", value: "MY"}
  ```

  This option shows `+60 Malaysia (MY)` in the dropdown and `+60` in the selected input, and submits `MY`. Focus, blur, Escape, and selection recovery retain the selected label. Options without `selected_label` use `label`.

  Use `tag_label` for a shorter tag label in tags and quick-tags modes:

  ```elixir
  [%{label: "New York", value: "NY", tag_label: "NY"}]
  ```

  ## Styling

  `style` supports `:tailwind` (the default), `:daisyui`, and `:none`. The consuming application provides its own CSS build. See the [styling guide](styling.md) for source scanning, defaults, and class overrides.

  ## Slots

  The `:option` and `:tag` slots receive the normalized option through `:let`. Options passed to the `:option` slot also contain `selected`, a boolean indicating whether the value is already selected.

  The following layout places an icon and label in explicit grid tracks. `globe/1` and `check/1` represent icon components supplied by the consuming application:

  ```heex
  <.live_select field={@form[:city_search]} phx-target={@myself} mode={:tags}>
    <:option :let={option}>
      <div class="grid grid-cols-[1rem_1fr] items-center gap-1">
        <.globe />
        <span>{option.label}</span>
      </div>
    </:option>
    <:tag :let={option}>
      <span class="grid grid-cols-[1rem_1fr] items-center gap-1">
        <.check />
        <span>{option.label}</span>
      </span>
    </:tag>
  </.live_select>
  ```

  The `:clear_button` slot supplies the content of the button used to clear a single selection or remove a tag:

  ```heex
  <.live_select field={@form[:city_search]} allow_clear>
    <:clear_button>
      Clear
    </:clear_button>
  </.live_select>
  ```

  Set `no_basic_styles_for_clear_buttons` when your custom button requires its own size and positioning.

  ## Controlling the selection

  Send a `value` update to replace the selection and trigger a form change event:

  ```elixir
  send_update(LiveSelect.Component, id: live_select_id, value: new_selection)
  ```

  Use a single value in single mode and a list in tags or quick-tags mode. Passing `nil` clears the selection. The `value` assign can also provide an initial selection and takes precedence over the form field's value.

  Pass `id` to set the component ID explicitly. Otherwise, the ID is `#{form_name}_#{field}_live_select_component`.

  ## Single selection example

  This example searches for cities and submits the selected city's coordinates. The form has the name `my_form`, and the field is `city_search`:

  ```heex
  <.form for={@form} phx-change="change">
    <.live_select field={@form[:city_search]} />
  </.form>
  ```

  If the target is a LiveComponent, pass `phx-target={@myself}` to LiveSelect and the form. Handle the search event in that target:

  ```elixir
  @impl true
  def handle_event("live_select_change", %{"text" => text, "id" => id}, socket) do
    options = City.search(text)

    send_update(LiveSelect.Component, id: id, options: options)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change", %{"my_form" => %{"city_search" => value}}, socket) do
    {:noreply, assign(socket, city_coordinates: LiveSelect.decode(value))}
  end
  ```

  `City.search/1` represents your application's search function. It can return `[{"New York City", [-74.00597, 40.71427]}]`. The coordinates are submitted as JSON and decoded into a list. The selected text is also available in the `city_search_text_input` parameter.

  ## Multiple selection example

  Set `mode={:tags}` to submit several cities:

  ```heex
  <.form for={@form} phx-change="change">
    <.live_select field={@form[:city_search]} mode={:tags} />
  </.form>
  ```

  The change handler receives a list of JSON-encoded coordinate lists. An empty selection submits a blank multiple-input placeholder, which `decode/1` removes:

  ```elixir
  @impl true
  def handle_event("change", %{"my_form" => params}, socket) do
    coordinates = LiveSelect.decode(params["city_search"])

    {:noreply, assign(socket, city_coordinates: coordinates)}
  end
  ```

  Use `mode={:quick_tags}` with the same change handler to keep the dropdown open between selections.

  ## Several fields in one LiveView

  The search event's `field` parameter distinguishes fields when they share the same callback:

  ```heex
  <.form for={@form} phx-change="change">
    <.live_select field={@form[:city_search]} />
    <.live_select field={@form[:album_search]} />
  </.form>
  ```

  ```elixir
  @impl true
  def handle_event("live_select_change", %{"text" => text, "id" => id, "field" => field}, socket) do
    options =
      case field do
        "my_form_city_search" -> City.search(text)
        "my_form_album_search" -> Album.search(text)
      end

    send_update(LiveSelect.Component, id: id, options: options)

    {:noreply, socket}
  end
  ```

  ## Associations and embeds

  LiveSelect supports Ecto association and embed values. Map them to options, then decode submitted values before casting them in the consuming application.

  The following schemas represent a temporary search form, so they do not persist records or require database timestamps:

  ```elixir
  defmodule City do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name, :string
      field :pos, {:array, :float}
    end

    def changeset(schema \\ %__MODULE__{}, params) do
      cast(schema, params, [:name, :pos])
    end
  end

  defmodule CitySearchForm do
    use Ecto.Schema

    import Ecto.Changeset

    embedded_schema do
      embeds_many :city_search, City, on_replace: :delete
    end

    def changeset(schema \\ %__MODULE__{}, params) do
      schema
      |> cast(params, [])
      |> cast_embed(:city_search)
    end
  end
  ```

  `value_mapper` receives each value from the form and returns the corresponding option. Return JSON-encodable values, such as a map containing the city's name and coordinates:

  ```heex
  <.live_select
    field={@form[:city_search]}
    mode={:tags}
    value_mapper={fn city -> %{label: city.name, value: %{name: city.name, pos: city.pos}} end}
  />
  ```

  Map search results into the same shape when handling search events:

  ```elixir
  @impl true
  def handle_event("live_select_change", %{"text" => text, "id" => id}, socket) do
    options =
      City.search(text)
      |> Enum.map(fn city -> %{label: city.name, value: %{name: city.name, pos: city.pos}} end)

    send_update(LiveSelect.Component, id: id, options: options)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change", %{"city_search_form" => params}, socket) do
    params = Map.update(params, "city_search", [], &LiveSelect.decode/1)
    changeset = CitySearchForm.changeset(params)

    {:noreply, assign(socket, form: to_form(changeset))}
  end
  ```

  The selected cities are JSON-decoded before `cast_embed/3` receives them. The same mapping and decoding pattern applies to associations owned by the consuming application.
  """

  @doc ~S"""
  Renders a LiveSelect input for a form field.

  See the [styling guide](styling.md) for the class attributes.
  """
  @doc type: :component

  attr(:field, :any, required: true, doc: "the Phoenix.HTML.FormField to render")
  attr(:form, :any, doc: false)

  attr(:id, :string,
    doc: ~S(the component ID, defaulting to `#{form_name}_#{field}_live_select_component`)
  )

  attr(:mode, :atom,
    values: [:single, :tags, :quick_tags],
    default: :single,
    doc: "single selection, removable tags, or tags with a dropdown that stays open"
  )

  attr(:options, :any,
    doc:
      "the initial enumerable of options, updated after rendering with Phoenix.LiveView.send_update/3"
  )

  attr(:keep_options_on_select, :boolean,
    doc: "preserve the current options and search text after selection"
  )

  attr(:keep_label_on_select, :boolean,
    default: false,
    doc: "keep the selected label visible while the single-mode input is focused"
  )

  attr(:value, :any,
    doc: "override the form selection with one value in single mode or a list in tags modes"
  )

  attr(:max_selectable, :integer,
    default: 0,
    doc: "the maximum number of selections, or 0 for unlimited selections"
  )

  attr(:user_defined_options, :boolean,
    default: false,
    doc: "allow Enter to select the search text when no dropdown option has priority"
  )

  attr(:dropdown_selectable_priority, :boolean,
    default: false,
    doc: "give the first selectable dropdown option priority over user-defined text on Enter"
  )

  attr(:allow_clear, :boolean, doc: "display a button to clear a single selection")
  attr(:disabled, :boolean, doc: "disable the component")
  attr(:placeholder, :string, doc: "the search input's placeholder")

  attr(:debounce, :integer,
    default: 100,
    doc: "the delay in milliseconds after typing before sending live_select_change"
  )

  attr(:value_mapper, :any, doc: "a callback mapping each form value to a JSON-encodable option")

  attr(:update_min_len, :integer,
    default: 1,
    doc: "the minimum search text length that triggers an option update"
  )

  attr(:style, :atom,
    values: [:tailwind, :daisyui, :none],
    default: :tailwind,
    doc: "the built-in style, or :none for application-provided CSS"
  )

  attr(:"phx-target", :any, doc: "the target for search, focus, and blur events")
  attr(:"phx-blur", :string, doc: "an event sent on blur with the component ID")
  attr(:"phx-focus", :string, doc: "an event sent on focus with the component ID")

  attr(:no_basic_styles_for_clear_buttons, :boolean,
    doc: "let application styles control clear-button sizing and positioning"
  )

  attr(:active_option_class, :any, doc: false)
  attr(:available_option_class, :any, doc: false)
  attr(:unavailable_option_class, :any, doc: false)
  attr(:clear_button_class, :any, doc: false)
  attr(:clear_button_extra_class, :any, doc: false)
  attr(:clear_tag_button_class, :any, doc: false)
  attr(:clear_tag_button_extra_class, :any, doc: false)
  attr(:container_class, :any, doc: false)
  attr(:container_extra_class, :any, doc: false)
  attr(:dropdown_class, :any, doc: false)
  attr(:dropdown_extra_class, :any, doc: false)
  attr(:option_class, :any, doc: false)
  attr(:option_extra_class, :any, doc: false)
  attr(:text_input_class, :any, doc: false)
  attr(:text_input_extra_class, :any, doc: false)
  attr(:text_input_selected_class, :any, doc: false)
  attr(:selected_option_class, :any, doc: false)
  attr(:tag_class, :any, doc: false)
  attr(:tag_extra_class, :any, doc: false)
  attr(:tags_container_class, :any, doc: false)
  attr(:tags_container_extra_class, :any, doc: false)

  slot(:option, doc: "a dropdown option, provided through :let with its selected state")
  slot(:tag, doc: "a selected tag, provided through :let")
  slot(:clear_button, doc: "custom content for selection and tag clear buttons")

  def live_select(assigns) do
    assigns =
      assigns
      |> update(:field, fn
        %Phoenix.HTML.FormField{} = field, _ ->
          field

        field, %{form: form} ->
          IO.warn(
            "instead of passing separate form and field attributes, pass a single field attribute of type Phoenix.HTML.FormField"
          )

          form = if is_atom(form), do: to_form(%{}, as: form), else: to_form(form)
          form[field]

        _, _ ->
          raise "if you pass field as atom or string, you also have to pass a form"
      end)
      |> assign_new(:id, fn %{field: field} ->
        "#{field.form.name}_#{field.field}_live_select_component"
      end)
      |> assign(module: Component)

    live_select_template(assigns)
  end

  @doc ~S"""
  Decodes JSON-encoded selection values received through form parameters.

  Use this for composite option values, such as maps or lists. A list of submitted values is decoded element by element, ignoring blank placeholders from empty multiple inputs. An absent tags field (`nil`) becomes an empty list, and an empty single field (`""`) becomes `nil`.

  ```elixir
  params = update_in(params, ~w(my_form my_field), &LiveSelect.decode/1)
  ```

  ## Examples

      iex> decode(nil)
      []

      iex> decode("")
      nil

      iex> decode("{\"name\":\"Berlin\",\"pos\":[13.41053,52.52437]}")
      %{"name" => "Berlin", "pos" => [13.41053, 52.52437]}

      iex> decode(["[-74.00597,40.71427]", "[18.06871,59.32938]"])
      [[-74.00597, 40.71427], [18.06871, 59.32938]]
  """
  def decode(selection) do
    json = Phoenix.json_library()

    case selection do
      nil ->
        []

      "" ->
        nil

      selection when is_list(selection) ->
        selection
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&json.decode!/1)

      selection ->
        json.decode!(selection)
    end
  end
end
