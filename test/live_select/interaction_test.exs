defmodule LiveSelect.InteractionTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  @endpoint LiveSelect.TestEndpoint
  @component_id "search_city_live_select_component"
  @component "#search_city_live_select_component"
  @input "#search_city_text_input"

  setup tags do
    {:ok, view, _html} =
      live_isolated(build_conn(), LiveSelect.TestLive,
        session: %{
          "component" => Map.new(tags[:component] || []),
          "source" => tags[:source] || %{},
          "owner" => self(),
          "search_options" => tags[:search_options]
        }
      )

    %{view: view}
  end

  @tag search_options: [{"Berlin", "BER"}, {"Bern", "BRN"}]
  test "search results sent by the parent become selectable form values", %{view: view} do
    view |> element(@component) |> render_hook("change", %{text: "Ber"})

    render_hook(view, "live_select_change", %{
      id: @component_id,
      field: "search_city",
      text: "Ber"
    })

    assert_receive {:search,
                    %{
                      "id" => @component_id,
                      "field" => "search_city",
                      "text" => "Ber"
                    }}

    assert render(view)
    assert has_element?(view, "#{@component} ul div[data-idx='0']", "Berlin")

    view |> element(@component) |> render_hook("option_click", %{idx: "0"})

    assert has_element?(view, "#search_city[name='search[city]'][value='BER']")
    assert has_element?(view, "#{@input}[value='Berlin']")
    refute has_element?(view, "#{@component} ul")

    assert_push_event(view, "select", %{
      id: @component_id,
      selection: [%{label: "Berlin", value: "BER"}],
      input_event: true,
      current_text: "Berlin"
    })
  end

  @tag component: [options: [{"Berlin", "BER"}, {"Bern", "BRN"}]]
  test "selection events match the committed DOM revision and advance on each update", %{
    view: view
  } do
    [initial_revision] =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(@component)
      |> LazyHTML.attribute("data-selection-revision")

    view |> element(@input) |> render_focus()
    assert_push_event(view, "select", %{revision: focused_revision})
    assert focused_revision > String.to_integer(initial_revision)
    assert has_element?(view, "#{@component}[data-selection-revision='#{focused_revision}']")

    view |> element(@component) |> render_hook("option_click", %{idx: "1"})
    assert_push_event(view, "select", %{revision: selected_revision, input_event: true})
    assert selected_revision > focused_revision
    assert has_element?(view, "#{@component}[data-selection-revision='#{selected_revision}']")
    assert has_element?(view, "#search_city[value='BRN']")
  end

  @tag component: [options: [{"Berlin", "BER"}, {"Bern", "BRN"}]]
  test "keyboard navigation selects the active option and requests scrolling", %{view: view} do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("keydown", %{key: "ArrowDown"})

    assert_push_event(view, "scroll_to_option", %{id: @component_id, idx: 0})

    view |> element(@component) |> render_hook("keydown", %{key: "ArrowDown"})
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    assert has_element?(view, "#search_city[value='BRN']")
    assert has_element?(view, "#{@input}[value='Bern']")
  end

  @tag component: [options: [{"Disabled", "off", true}, {"Berlin", "BER"}, {"Bern", "BRN"}]]
  test "keyboard navigation follows the displayed order and skips disabled options", %{view: view} do
    view |> element(@input) |> render_focus()

    view
    |> element(@component)
    |> render_hook("keydown", %{key: "ArrowDown", visual_order: [2, 0, 1]})

    assert_push_event(view, "scroll_to_option", %{idx: 2})

    view
    |> element(@component)
    |> render_hook("keydown", %{key: "ArrowDown", visual_order: [2, 0, 1]})

    assert_push_event(view, "scroll_to_option", %{idx: 1})

    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})
    assert has_element?(view, "#search_city[value='BER']")
  end

  @tag component: [options: [{"Disabled", "off", true}, {"Berlin", "BER"}]]
  test "disabled options cannot be selected with the pointer", %{view: view} do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("option_click", %{idx: "0"})

    assert has_element?(view, "#search_city[value='']")
    assert has_element?(view, "#{@component} ul")

    view |> element(@component) |> render_hook("option_click", %{idx: "1"})
    assert has_element?(view, "#search_city[value='BER']")
  end

  @tag component: [options: [{"Berlin", "BER"}]]
  test "Enter selects the only result without arrow navigation", %{view: view} do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    assert has_element?(view, "#search_city[value='BER']")
  end

  @tag component: [options: [{"Berlin", "BER"}, {"Bern", "BRN"}]]
  test "Enter leaves multiple results unselected until an option is active", %{view: view} do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    assert has_element?(view, "#search_city[value='']")
    assert has_element?(view, "#{@component} ul")
  end

  @tag component: [dropdown_selectable_priority: true, user_defined_options: true]
  test "Enter waits for the current search and gives selectable results priority", %{view: view} do
    view |> element(@component) |> render_hook("change", %{text: "Ber"})
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})
    assert has_element?(view, "#search_city[value='']")

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: [{"Disabled", "off", true}, {"Berlin", "BER"}, {"Bern", "BRN"}]
    )

    assert render(view)
    assert has_element?(view, "#search_city[value='BER']")
  end

  @tag component: [dropdown_selectable_priority: true, user_defined_options: true]
  test "an empty search result allows queued Enter to select user-defined text", %{view: view} do
    view |> element(@component) |> render_hook("change", %{text: "Bruges"})
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component, id: @component_id, options: [])

    assert render(view)
    assert has_element?(view, "#search_city[value='Bruges']")
  end

  @tag component: [dropdown_selectable_priority: true, user_defined_options: true]
  test "clearing the search cancels a queued Enter", %{view: view} do
    view |> element(@component) |> render_hook("change", %{text: "Ber"})
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})
    view |> element(@component) |> render_hook("options_clear", %{})

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: [{"Berlin", "BER"}]
    )

    assert render(view)
    assert has_element?(view, "#search_city[value='']")
  end

  for mode <- [:single, :tags, :quick_tags],
      cancellation <- [:escape, :blur, :self_blur, :change] do
    @tag component: [
           mode: mode,
           dropdown_selectable_priority: true,
           user_defined_options: true
         ]
    @tag source: %{"city" => if(mode == :single, do: "ORIGINAL", else: ["ORIGINAL"])}
    @cancellation cancellation
    test "#{mode} cancels a queued Enter after #{cancellation}", %{view: view} do
      view |> element(@component) |> render_hook("change", %{text: "Ber"})
      view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

      case @cancellation do
        :escape ->
          view |> element(@component) |> render_hook("keydown", %{key: "Escape"})

        :blur ->
          view |> element(@input) |> render_blur()

        :self_blur ->
          view |> element(@component) |> render_hook("self_blur", %{})

        :change ->
          view |> element(@component) |> render_hook("change", %{text: "Berlin"})
      end

      Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
        id: @component_id,
        options: [{"Berlin", "BER"}]
      )

      values =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("input[type=hidden]")
        |> LazyHTML.attribute("value")

      assert values == ["ORIGINAL"]
    end
  end

  @tag component: [
         allow_clear: true,
         dropdown_selectable_priority: true,
         user_defined_options: true
       ]
  @tag source: %{"city" => "ORIGINAL"}
  test "clearing a selection cancels a queued Enter", %{view: view} do
    view |> element(@component) |> render_hook("change", %{text: "Ber"})
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})
    view |> element("button[aria-label='Clear selection']") |> render_click()

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: [{"Berlin", "BER"}]
    )

    assert render(view)
    assert has_element?(view, "#search_city[value='']")
    refute has_element?(view, "button[aria-label='Clear selection']")
  end

  for {mode, value, expected_values} <- [
        {:single, "SERVER", ["SERVER"]},
        {:single, nil, [""]},
        {:tags, ["SERVER"], ["SERVER"]},
        {:tags, nil, [""]},
        {:quick_tags, ["SERVER"], ["SERVER"]},
        {:quick_tags, nil, [""]}
      ] do
    @tag component: [
           mode: mode,
           dropdown_selectable_priority: true,
           user_defined_options: true
         ]
    @tag source: %{"city" => if(mode == :single, do: "ORIGINAL", else: ["ORIGINAL"])}
    @value value
    @expected_values expected_values
    test "#{mode} keeps an explicit #{if is_nil(value), do: "clear", else: "replacement"} when queued search results arrive",
         %{view: view} do
      view |> element(@component) |> render_hook("change", %{text: "Ber"})
      view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

      Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
        id: @component_id,
        value: @value
      )

      assert render(view)

      Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
        id: @component_id,
        options: [{"Berlin", "BER"}]
      )

      values =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("input[type=hidden]")
        |> LazyHTML.attribute("value")

      assert values == @expected_values
    end
  end

  @tag component: [options: ["Berlin", "Bern", "Bruges"]]
  test "a smaller result set clears an active option that no longer exists", %{view: view} do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("keydown", %{key: "ArrowUp"})
    assert_push_event(view, "scroll_to_option", %{idx: 2})

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: ["Bremen", "Bonn"]
    )

    assert render(view)
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    assert has_element?(view, "#search_city[value='']")
    assert has_element?(view, "#{@component} ul div[data-idx='0']", "Bremen")
  end

  @tag component: [options: ["Berlin"]]
  test "a pointer event for an option removed by a search update is ignored", %{view: view} do
    view |> element(@input) |> render_focus()

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component, id: @component_id, options: [])

    assert render(view)
    view |> element(@component) |> render_hook("option_click", %{idx: "0"})
    assert has_element?(view, "#search_city[value='']")
  end

  @tag component: [options: [{"Berlin", "BER"}], allow_clear: true]
  test "the clear button removes the selected form value", %{view: view} do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("option_click", %{idx: "0"})
    view |> element("button[aria-label='Clear selection']") |> render_click()

    assert has_element?(view, "#search_city[value='']")
    assert has_element?(view, "#{@input}[value='']")
    refute has_element?(view, "button[aria-label='Clear selection']")

    assert_push_event(view, "select", %{selection: [], input_event: true, current_text: ""})
  end

  @tag component: [
         options: [
           %{label: "+1 United States (US)", selected_label: "+1", value: "US"},
           %{label: "+1 Canada (CA)", selected_label: "+1", value: "CA"}
         ],
         keep_options_on_select: true,
         keep_label_on_select: true,
         "phx-focus": "city-focus",
         "phx-blur": "city-blur"
       ]
  test "selected labels survive focus, blur, and Escape without changing submitted values", %{
    view: view
  } do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("option_click", %{idx: "1"})

    assert has_element?(view, "#search_city[value='CA']")
    assert has_element?(view, "#{@input}[value='+1']")

    view |> element(@input) |> render_focus()
    assert_push_event(view, "select", %{parent_event: "city-focus", current_text: "+1"})

    view |> element(@component) |> render_hook("change", %{text: "United"})
    view |> element(@input) |> render_blur()
    assert_push_event(view, "select", %{parent_event: "city-blur", current_text: "+1"})
    refute has_element?(view, "#{@component} ul")

    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("keydown", %{key: "Escape"})
    assert_push_event(view, "select", %{current_text: "+1"})
    assert has_element?(view, "#search_city[value='CA']")
    refute has_element?(view, "#{@component} ul")
  end

  @tag component: [options: [{"Initial", "initial"}], keep_options_on_select: true]
  test "a parent form rerender preserves current search results and selection labels", %{
    view: view
  } do
    view |> element(@input) |> render_focus()

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: [{"Berlin", "BER"}, {"Bern", "BRN"}]
    )

    assert render(view)
    view |> element(@component) |> render_hook("option_click", %{idx: "0"})
    view |> element(@input) |> render_focus()
    view |> form("#search-form") |> render_change()

    assert_receive {:form_change, %{"city" => "BER"}}
    assert has_element?(view, "#search_city[value='BER']")
    assert has_element?(view, "#{@input}[value='Berlin']")
    assert has_element?(view, "#{@component} ul div[data-idx='1']", "Bern")
    refute has_element?(view, "#{@component} ul li", "Initial")
  end

  test "programmatic values replace and clear the selection through normal client events", %{
    view: view
  } do
    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: [%{label: "Malaysia", selected_label: "+60", value: "MY"}],
      value: "MY"
    )

    assert render(view)
    assert has_element?(view, "#search_city[value='MY']")
    assert has_element?(view, "#{@input}[value='+60']")
    assert_push_event(view, "select", %{input_event: true, current_text: "+60"})

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component, id: @component_id, value: nil)

    assert render(view)
    assert has_element?(view, "#search_city[value='']")
    assert_push_event(view, "select", %{selection: [], input_event: true, current_text: ""})
  end

  @tag source: %{"city" => "MY"}
  test "reconnection recovers display metadata for the server's selected value", %{view: view} do
    view
    |> element(@component)
    |> render_hook("selection_recovery", [
      %{label: "+60 Malaysia (MY)", selected_label: "+60", value: "MY"},
      %{label: "+1 Canada (CA)", selected_label: "+1", value: "CA"}
    ])

    assert has_element?(view, "#search_city[value='MY']")
    assert has_element?(view, "#{@input}[value='+60']")
    assert_push_event(view, "select", %{selection: [%{value: "MY"}], input_event: false})

    view |> element(@input) |> render_focus()
    assert has_element?(view, "#{@component} ul li", "+60 Malaysia (MY)")
    refute has_element?(view, "#{@component} ul li", "+1 Canada (CA)")
  end

  @tag component: [
         options: [%{label: "Malaysia", selected_label: "+60", value: "MY"}]
       ]
  @tag source: %{"city" => "MY"}
  test "reconnection keeps option metadata supplied by the server", %{view: view} do
    view
    |> element(@component)
    |> render_hook("selection_recovery", [%{label: "Old label", value: "MY"}])

    assert has_element?(view, "#{@input}[value='+60']")
    view |> element(@input) |> render_focus()
    assert has_element?(view, "#{@component} ul li", "Malaysia")
    refute has_element?(view, "#{@component} ul li", "Old label")
  end

  @tag component: [mode: :tags, options: [{"Berlin", "BER"}, {"Bern", "BRN"}]]
  test "tags select multiple values, prevent duplicates, and return to an empty form marker", %{
    view: view
  } do
    for idx <- ["0", "1"] do
      view |> element(@input) |> render_focus()

      Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
        id: @component_id,
        options: [{"Berlin", "BER"}, {"Bern", "BRN"}]
      )

      assert render(view)
      view |> element(@component) |> render_hook("option_click", %{idx: idx})
    end

    assert has_element?(view, "#search_city_0[name='search[city][]'][value='BER']")
    assert has_element?(view, "#search_city_1[name='search[city][]'][value='BRN']")
    refute has_element?(view, "input[data-live-select-empty]")

    view |> element(@input) |> render_focus()

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component,
      id: @component_id,
      options: [{"Berlin", "BER"}, {"Bern", "BRN"}]
    )

    assert render(view)
    refute has_element?(view, "#{@component} ul div[data-idx]")
    view |> element(@component) |> render_hook("keydown", %{key: "ArrowDown"})
    assert_push_event(view, "scroll_to_option", %{idx: -1})

    view |> element("button[aria-label='Remove selection'][data-idx='0']") |> render_click()
    assert has_element?(view, "#search_city_0[value='BRN']")

    view |> element("button[aria-label='Remove selection'][data-idx='0']") |> render_click()
    assert has_element?(view, "#search_city_empty_selection[data-live-select-empty]")
    refute has_element?(view, "input[name='search[city][]']:not([data-live-select-empty])")
  end

  for mode <- [:tags, :quick_tags] do
    @tag component: [mode: mode, options: [{"Berlin", "BER"}]]
    @tag source: %{"city" => ["BER"]}
    test "removing the final #{mode} selection clears an existing Ecto array through the form", %{
      view: view
    } do
      view |> element("button[aria-label='Remove selection']") |> render_click()
      view |> form("#search-form") |> render_change()

      assert_receive {:form_change, params}

      changeset =
        Ecto.Changeset.cast({%{city: ["BER"]}, %{city: {:array, :string}}}, params, [:city])

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :city) == []
      assert params["city"] == [""]
      assert has_element?(view, "#search_city_empty_selection[data-live-select-empty]")
      refute has_element?(view, "button[aria-label='Remove selection']")
    end
  end

  @tag component: [
         mode: :tags,
         max_selectable: 1,
         keep_options_on_select: true,
         options: [{"Berlin", "BER"}, {"Bern", "BRN"}]
       ]
  test "a tag selection limit blocks additional choices until a selection is removed", %{
    view: view
  } do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("option_click", %{idx: "0"})
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("option_click", %{idx: "1"})

    assert has_element?(view, "#search_city_0[value='BER']")
    refute has_element?(view, "#search_city_1")

    view |> element("button[aria-label='Remove selection']") |> render_click()
    view |> element(@component) |> render_hook("option_click", %{idx: "1"})

    assert has_element?(view, "#search_city_0[value='BRN']")
  end

  @tag component: [
         mode: :tags,
         options: [%{label: "Berlin", tag_label: "BER", value: "BER", sticky: true}]
       ]
  @tag source: %{"city" => ["BER"]}
  test "sticky tags retain their display label and can still be replaced programmatically", %{
    view: view
  } do
    assert has_element?(view, @component, "BER")
    refute has_element?(view, "button[aria-label='Remove selection']")

    Phoenix.LiveView.send_update(view.pid, LiveSelect.Component, id: @component_id, value: nil)

    assert render(view)
    assert has_element?(view, "input[data-live-select-empty]")
    refute has_element?(view, "#search_city_0")
  end

  @tag component: [
         mode: :quick_tags,
         max_selectable: 1,
         options: [{"Berlin", "BER"}, {"Bern", "BRN"}]
       ]
  test "quick tags keep results open and toggle selections while respecting the limit", %{
    view: view
  } do
    view |> element(@input) |> render_focus()
    view |> element(@component) |> render_hook("option_click", %{idx: "0"})

    assert has_element?(view, "#search_city_0[value='BER']")
    assert has_element?(view, "#{@component} ul div[data-idx='0']", "Berlin")

    view |> element(@component) |> render_hook("option_click", %{idx: "1"})
    refute has_element?(view, "#search_city_1")

    view |> element(@component) |> render_hook("option_click", %{idx: "0"})
    assert has_element?(view, "input[data-live-select-empty]")
    assert has_element?(view, "#{@component} ul")

    view |> element(@component) |> render_hook("option_click", %{idx: "1"})
    assert has_element?(view, "#search_city_0[value='BRN']")

    view |> element(@input) |> render_blur()
    assert has_element?(view, "#{@component} ul")

    view |> element(@component) |> render_hook("self_blur", %{})
    refute has_element?(view, "#{@component} ul")
  end

  @tag component: [
         mode: :quick_tags,
         options: [%{label: "Berlin", value: "BER", sticky: true}, {"Bern", "BRN"}]
       ]
  @tag source: %{"city" => ["BER"]}
  test "quick tag navigation skips sticky selections and can deselect other tags", %{view: view} do
    view |> element(@input) |> render_focus()
    refute has_element?(view, "#{@component} ul div[data-idx='0']")

    view |> element(@component) |> render_hook("keydown", %{key: "ArrowDown"})
    assert_push_event(view, "scroll_to_option", %{idx: 1})
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    assert has_element?(view, "#search_city_1[value='BRN']")
    view |> element(@component) |> render_hook("keydown", %{key: "Enter"})

    assert has_element?(view, "#search_city_0[value='BER']")
    refute has_element?(view, "#search_city_1")
  end
end
