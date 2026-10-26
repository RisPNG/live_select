defmodule LiveSelect.ComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2, to_form: 2]
  import Phoenix.LiveViewTest

  setup do
    %{form: to_form(%{}, as: :search)}
  end

  test "renders native search and submission controls with hook configuration", %{form: form} do
    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        id: "city-picker",
        placeholder: "Search cities",
        debounce: 250,
        update_min_len: 2,
        "phx-target": "#address"
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.attribute(LazyHTML.query(html, "#city-picker"), "phx-hook") == ["LiveSelect"]

    assert LazyHTML.attribute(LazyHTML.query(html, "#city-picker"), "data-field") == [
             "search_city"
           ]

    assert LazyHTML.attribute(LazyHTML.query(html, "#city-picker"), "data-debounce") == ["250"]

    assert LazyHTML.attribute(LazyHTML.query(html, "#city-picker"), "data-update-min-len") == [
             "2"
           ]

    assert LazyHTML.attribute(LazyHTML.query(html, "#city-picker"), "data-phx-target") == [
             "#address"
           ]

    input = LazyHTML.query(html, "input[type=text]")
    assert LazyHTML.attribute(input, "id") == ["search_city_text_input"]
    assert LazyHTML.attribute(input, "name") == ["search[city_text_input]"]
    assert LazyHTML.attribute(input, "placeholder") == ["Search cities"]
    assert LazyHTML.attribute(input, "autocomplete") == ["off"]

    hidden = LazyHTML.query(html, "input[type=hidden]")
    assert LazyHTML.attribute(hidden, "id") == ["search_city"]
    assert LazyHTML.attribute(hidden, "name") == ["search[city]"]
    assert LazyHTML.attribute(hidden, "value") == [""]
  end

  test "derives control names and IDs from nested form fields" do
    form = to_form(%{"city" => "MY"}, as: "search[address]", id: "search_address")

    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        options: [{"Malaysia", "MY"}]
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "id") ==
             ["search_address_city_text_input"]

    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "name") ==
             ["search[address][city_text_input]"]

    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "name") ==
             ["search[address][city]"]
  end

  test "normalizes supported option representations and uses their labels", %{form: form} do
    for options <- [
          [{"Malaysia", "MY"}],
          [%{label: "Malaysia", value: "MY"}],
          [[label: "Malaysia", value: "MY"]],
          [%{key: "Malaysia", value: "MY"}],
          %{"Malaysia" => "MY"},
          Stream.map(["MY"], &{"Malaysia", &1})
        ] do
      html =
        render_component(&LiveSelect.live_select/1,
          field: form[:city],
          options: options,
          value: "MY",
          hide_dropdown: false
        )
        |> LazyHTML.from_fragment()

      assert LazyHTML.query(html, "ul li") |> LazyHTML.text() |> String.trim() == "Malaysia"
      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "value") == ["Malaysia"]
      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == ["MY"]
    end
  end

  test "accepts scalar options, value-only options, ranges, and keyword enumerables", %{
    form: form
  } do
    for {options, value, label} <- [
          {["Malaysia"], "Malaysia", "Malaysia"},
          {[:Malaysia], :Malaysia, "Malaysia"},
          {[12.5], 12.5, "12.5"},
          {[%{value: "MY"}], "MY", "MY"},
          {[[value: "MY"]], "MY", "MY"},
          {1..3, 2, "2"},
          {[Malaysia: "MY"], "MY", "Malaysia"}
        ] do
      html =
        render_component(&LiveSelect.live_select/1,
          field: form[:city],
          options: options,
          value: value
        )
        |> LazyHTML.from_fragment()

      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "value") == [label]

      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == [
               to_string(value)
             ]
    end
  end

  test "submits composite values as JSON in single and tag modes", %{form: form} do
    city = %{"name" => "New York", "coordinates" => [-74.00597, 40.71427]}
    options = [%{label: "New York", value: city}]

    for {mode, value} <- [single: city, tags: [city], quick_tags: [city]] do
      html =
        render_component(&LiveSelect.live_select/1,
          field: form[:city],
          options: options,
          mode: mode,
          value: value
        )
        |> LazyHTML.from_fragment()

      assert [encoded] = LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value")
      assert LiveSelect.decode(encoded) == city

      expected_name = if mode == :single, do: "search[city]", else: "search[city][]"

      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "name") == [
               expected_name
             ]
    end
  end

  test "renders alternative selected labels separately from dropdown labels" do
    form = to_form(%{"city" => "MY"}, as: :search)

    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        options: [%{label: "+60 Malaysia (MY)", selected_label: "+60", value: "MY"}],
        hide_dropdown: false
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "value") == ["+60"]
    assert LazyHTML.query(html, "ul") |> LazyHTML.text() |> String.trim() == "+60 Malaysia (MY)"
    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == ["MY"]
  end

  test "an explicit value overrides the form, including an explicit clear" do
    form = to_form(%{"city" => "MY"}, as: :search)

    for {value, expected} <- [{"SG", "SG"}, {nil, ""}] do
      html =
        render_component(&LiveSelect.live_select/1, field: form[:city], value: value)
        |> LazyHTML.from_fragment()

      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == [expected]
    end
  end

  test "renders an empty-selection control for multiple selections", %{form: form} do
    for mode <- [:tags, :quick_tags] do
      html =
        render_component(&LiveSelect.live_select/1, field: form[:city], mode: mode)
        |> LazyHTML.from_fragment()

      hidden = LazyHTML.query(html, "input[type=hidden]")
      assert LazyHTML.attribute(hidden, "id") == ["search_city_empty_selection"]
      assert LazyHTML.attribute(hidden, "name") == ["search[city][]"]
      assert LazyHTML.attribute(hidden, "value") == [""]
      assert Enum.count(LazyHTML.query(html, "input[data-live-select-empty]")) == 1
    end
  end

  test "renders tag labels, native removal buttons, and sticky selections", %{form: form} do
    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        mode: :tags,
        options: [
          %{label: "Kuala Lumpur", tag_label: "KL", value: "KUL", sticky: true},
          %{label: "Singapore", tag_label: "SG", value: "SIN"}
        ],
        value: ["KUL", "SIN"]
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.text(html) =~ "KL"
    assert LazyHTML.text(html) =~ "SG"

    assert LazyHTML.attribute(
             LazyHTML.query(html, "button[phx-click=option_remove]"),
             "phx-value-idx"
           ) == ["1"]

    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == [
             "KUL",
             "SIN"
           ]

    assert Enum.empty?(LazyHTML.query(html, "input[data-live-select-empty]"))
  end

  test "disabled controls are excluded from native form submission and cannot be cleared", %{
    form: form
  } do
    for {mode, value} <- [single: "MY", tags: ["MY"], quick_tags: ["MY"]] do
      html =
        render_component(&LiveSelect.live_select/1,
          field: form[:city],
          mode: mode,
          value: value,
          disabled: true,
          allow_clear: true
        )
        |> LazyHTML.from_fragment()

      assert Enum.count(LazyHTML.query(html, "input:disabled")) == 2
      assert Enum.empty?(LazyHTML.query(html, "button"))
    end
  end

  test "maps Ecto changeset values and omits replaced embeds", %{form: form} do
    city = %{name: "Kuala Lumpur", code: "KUL"}
    changeset = Ecto.Changeset.change({city, %{name: :string, code: :string}}, name: "KL")
    replaced = %{changeset | action: :replace}

    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        mode: :tags,
        value: [changeset, replaced],
        value_mapper: fn city -> %{label: city.name, value: city.code} end
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.text(html) =~ "KL"
    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == ["KUL"]
  end

  test "passes normalized options and selected state to slots", %{form: form} do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <LiveSelect.live_select
            field={@field}
            options={@options}
            value="MY"
            mode={:tags}
            hide_dropdown={false}
          >
            <:option :let={option}>
              <span data-selected={to_string(option.selected)}>{option.label}:{option.value}</span>
            </:option>
            <:tag :let={option}>
              <strong>{option.tag_label}</strong>
            </:tag>
            <:clear_button>Remove city</:clear_button>
          </LiveSelect.live_select>
          """
        end,
        field: form[:city],
        options: [[label: "Malaysia", value: "MY", tag_label: "MY"], {"Singapore", "SG"}]
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.query(html, "ul [data-selected=true]") |> LazyHTML.text() |> String.trim() ==
             "Malaysia:MY"

    assert LazyHTML.query(html, "ul [data-selected=false]") |> LazyHTML.text() |> String.trim() ==
             "Singapore:SG"

    assert LazyHTML.query(html, "strong") |> LazyHTML.text() == "MY"
    assert LazyHTML.query(html, "button") |> LazyHTML.text() |> String.trim() == "Remove city"
  end

  test "escapes option labels, values, and placeholders", %{form: form} do
    unsafe = ~s|<script>alert("city")</script>|

    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        options: [{unsafe, unsafe}],
        value: unsafe,
        placeholder: unsafe,
        hide_dropdown: false
      )
      |> LazyHTML.from_fragment()

    assert Enum.empty?(LazyHTML.query(html, "script"))
    assert LazyHTML.query(html, "ul") |> LazyHTML.text() |> String.trim() == unsafe
    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == [unsafe]
    assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "placeholder") == [unsafe]
  end

  test "supports class overrides and extending defaults without duplicating classes", %{
    form: form
  } do
    html =
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        container_class: ["search-select"],
        text_input_extra_class: "!rounded-md search-input w-full"
      )
      |> LazyHTML.from_fragment()

    assert LazyHTML.attribute(LazyHTML.query(html, "[phx-hook]"), "class") == ["search-select"]
    [classes] = LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "class")
    classes = String.split(classes)
    assert "search-input" in classes
    refute "rounded-md" in classes
    assert Enum.count(classes, &(&1 == "w-full")) == 1
  end

  test "uses stylesheet classes for input and clear-button layout", %{form: form} do
    for style <- [:tailwind, :daisyui, :none],
        {mode, value, button_class} <- [
          {:single, "MY", "ls-clear-button"},
          {:tags, ["MY"], "ls-clear-tag-button"},
          {:quick_tags, ["MY"], "ls-clear-tag-button"}
        ] do
      html =
        render_component(&LiveSelect.live_select/1,
          field: form[:city],
          mode: mode,
          value: value,
          style: style,
          allow_clear: true
        )
        |> LazyHTML.from_fragment()

      assert Enum.count(LazyHTML.query(html, ".ls-input-container > input.ls-text-input")) == 1
      assert Enum.count(LazyHTML.query(html, "button.#{button_class}")) == 1
      assert Enum.empty?(LazyHTML.query(html, "[style]"))

      if mode == :single do
        assert Enum.count(LazyHTML.query(html, ".ls-input-container > button.ls-clear-button")) ==
                 1
      end
    end
  end

  test "supports application-owned styles and clear-button layout", %{form: form} do
    for {mode, value, button_label} <- [
          {:single, "MY", "Clear selection"},
          {:tags, ["MY"], "Remove selection"},
          {:quick_tags, ["MY"], "Remove selection"}
        ] do
      html =
        render_component(&LiveSelect.live_select/1,
          field: form[:city],
          mode: mode,
          value: value,
          style: :none,
          allow_clear: true,
          no_basic_styles_for_clear_buttons: true,
          text_input_class: "search-input",
          clear_button_class: "search-clear",
          clear_tag_button_class: "search-clear"
        )
        |> LazyHTML.from_fragment()

      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=text]"), "class") == [
               "search-input"
             ]

      assert LazyHTML.attribute(LazyHTML.query(html, "button"), "class") == ["search-clear"]
      assert LazyHTML.attribute(LazyHTML.query(html, "button"), "aria-label") == [button_label]
      assert Enum.empty?(LazyHTML.query(html, "[style]"))

      assert Enum.empty?(
               LazyHTML.query(
                 html,
                 ".ls-input-container, .ls-text-input, .ls-clear-button, .ls-clear-tag-button"
               )
             )
    end
  end

  test "rejects incompatible style configuration", %{form: form} do
    assert_raise RuntimeError, ~r/can't be used together/, fn ->
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        container_class: "search-select",
        container_extra_class: "search-border"
      )
    end

    assert_raise RuntimeError, ~r/style: :none/, fn ->
      render_component(&LiveSelect.live_select/1,
        field: form[:city],
        style: :none,
        container_extra_class: "search-select"
      )
    end
  end

  test "reports invalid component configuration", %{form: form} do
    for {attrs, message} <- [
          {[mode: :multiple], ~r/Invalid mode/},
          {[style: :bootstrap], ~r/Invalid style/},
          {[update_min_len: -1], ~r/Invalid update_min_len/},
          {[options: :not_enumerable], ~r/options must be enumerable/},
          {[options: [%{label: "Missing value"}]], ~r/invalid element in options/},
          {[placehoder: "Search"], ~r/Did you mean "placeholder"/}
        ] do
      assert_raise RuntimeError, message, fn ->
        render_component(&LiveSelect.live_select/1, [field: form[:city]] ++ attrs)
      end
    end
  end
end
