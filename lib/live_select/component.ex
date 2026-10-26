defmodule LiveSelect.Component do
  @moduledoc "The module that implements the `LiveSelect` live component"

  use Phoenix.LiveComponent

  import LiveSelect.ClassUtil

  @required_assigns ~w(field)a

  @default_opts [
    active_option_class: nil,
    allow_clear: false,
    available_option_class: nil,
    unavailable_option_class: nil,
    clear_button_class: nil,
    clear_button_extra_class: nil,
    clear_tag_button_class: nil,
    clear_tag_button_extra_class: nil,
    keep_options_on_select: false,
    keep_label_on_select: false,
    current_text: "",
    user_defined_options: false,
    container_class: nil,
    container_extra_class: nil,
    debounce: 100,
    disabled: false,
    dropdown_selectable_priority: false,
    dropdown_class: nil,
    dropdown_extra_class: nil,
    max_selectable: 0,
    mode: :single,
    no_basic_styles_for_clear_buttons: false,
    option_class: nil,
    option_extra_class: nil,
    options: [],
    placeholder: nil,
    selected_option_class: nil,
    style: :tailwind,
    tag_class: nil,
    tag_extra_class: nil,
    tags_container_class: nil,
    tags_container_extra_class: nil,
    text_input_class: nil,
    text_input_extra_class: nil,
    text_input_selected_class: nil,
    update_min_len: 1,
    value: nil
  ]

  @styles [
    tailwind: [
      active_option: ~W(text-white bg-gray-600),
      available_option: ~W(cursor-pointer hover:bg-gray-400 rounded),
      unavailable_option: ~W(text-gray-400),
      clear_button: ~W(cursor-pointer),
      clear_tag_button: ~W(cursor-pointer),
      container: ~W(h-full text-black relative),
      dropdown: ~W(absolute rounded-md shadow z-50 bg-gray-100 inset-x-0 top-full),
      option: ~W(rounded px-4 py-1),
      selected_option: ~W(cursor-pointer font-bold hover:bg-gray-400 rounded),
      text_input:
        ~W(rounded-md w-full disabled:bg-gray-100 disabled:placeholder:text-gray-400 disabled:text-gray-400 pr-6),
      text_input_selected: ~W(border-gray-600 text-gray-600),
      tags_container: ~W(flex flex-wrap gap-1 p-1),
      tag: ~w|p-1 text-sm rounded-lg bg-blue-400 grid grid-cols-[minmax(0,1fr)_auto] items-center|
    ],
    daisyui: [
      active_option: ~W(menu-active),
      available_option: ~W(cursor-pointer),
      unavailable_option: ~W(menu-disabled),
      clear_button: ~W(cursor-pointer),
      clear_tag_button: ~W(cursor-pointer),
      container: ~W(dropdown dropdown-open),
      dropdown: ~W(dropdown-content z-[1] menu menu-sm shadow rounded-box bg-base-200 p-1 w-full),
      option: nil,
      selected_option: ~W(cursor-pointer font-bold),
      text_input: ~W(input w-full pr-6),
      text_input_selected: ~W(input-primary),
      tags_container: ~W(flex flex-wrap gap-1 p-1),
      tag: ~w|p-1.5 text-sm badge badge-primary grid grid-cols-[minmax(0,1fr)_auto] items-center|
    ],
    none: []
  ]

  @modes ~w(single tags quick_tags)a

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(
        active_option: -1,
        hide_dropdown: true,
        pending_enter: false,
        awaiting_update: true,
        selection: [],
        value_mapper: &Function.identity/1
      )

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    if Map.has_key?(assigns, :style) && assigns.style not in Keyword.keys(@styles) do
      raise ~s(Invalid style: #{inspect(assigns.style)}. Style must be one of: #{inspect(Keyword.keys(@styles))})
    end

    if Map.has_key?(assigns, :mode) && assigns.mode not in @modes do
      raise ~s(Invalid mode: "#{assigns.mode}". Mode must be one of: #{inspect(@modes)})
    end

    if Map.has_key?(assigns, :update_min_len) &&
         (!is_integer(assigns.update_min_len) || assigns.update_min_len < 0) do
      raise ~s(Invalid update_min_len: "#{assigns.update_min_len}". It must be a non-negative integer)
    end

    if Map.has_key?(assigns, :options) && !Enumerable.impl_for(assigns.options) do
      raise "options must be enumerable"
    end

    valid_assigns =
      Keyword.keys(@default_opts) ++
        @required_assigns ++
        [
          :id,
          :options,
          :"phx-target",
          :"phx-blur",
          :"phx-focus",
          :option,
          :tag,
          :clear_button,
          :hide_dropdown,
          :value_mapper,
          :form
        ]

    for {assign, _} <- assigns_to_attributes(assigns), assign not in valid_assigns do
      most_similar =
        Enum.max_by(valid_assigns, &String.jaro_distance(to_string(&1), to_string(assign)))

      raise ~s(Invalid assign: "#{assign}". Did you mean "#{most_similar}"?)
    end

    assigns =
      if Map.has_key?(socket.assigns, :field) && Map.has_key?(assigns, :field) do
        Map.delete(assigns, :options)
      else
        assigns
      end

    socket =
      socket
      |> assign(assigns)
      |> update(:awaiting_update, fn
        _, %{options: _} -> false
        awaiting_update, _ -> awaiting_update
      end)

    for required <- @required_assigns do
      unless socket.assigns[required] do
        raise ~s/Missing required assign "#{required}"/
      end
    end

    socket =
      @default_opts
      |> Enum.reduce(socket, fn {opt, default}, socket ->
        socket
        |> assign_new(opt, fn -> default end)
      end)
      |> update(:options, &normalize_options/1)
      |> then(fn socket ->
        if Map.has_key?(assigns, :options) &&
             socket.assigns.active_option >= length(socket.assigns.options) do
          assign(socket, active_option: -1)
        else
          socket
        end
      end)

    socket =
      if field = assigns[:field] do
        update(
          socket,
          :selection,
          fn selection, %{options: options, mode: mode, value_mapper: value_mapper} ->
            update_selection(
              field.value,
              selection,
              options,
              mode,
              value_mapper
            )
          end
        )
      else
        socket
      end

    socket =
      if Map.has_key?(assigns, :value) do
        socket =
          update(socket, :selection, fn
            selection,
            %{options: options, value: value, mode: mode, value_mapper: value_mapper} ->
              update_selection(value, selection, options, mode, value_mapper)
          end)

        client_select(socket, %{
          input_event: true,
          current_text:
            case socket.assigns do
              %{mode: :single, selection: [option | _]} ->
                option[:selected_label] || option.label

              %{keep_options_on_select: true, current_text: text} ->
                text

              %{mode: :quick_tags, current_text: text} ->
                text

              _ ->
                ""
            end
        })
      else
        socket
      end

    socket =
      if Map.has_key?(assigns, :options) && socket.assigns.pending_enter do
        select_on_enter(socket, Enum.to_list(0..(length(socket.assigns.options) - 1)//1))
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("blur", _params, socket) do
    socket =
      socket
      |> assign(
        :hide_dropdown,
        if(socket.assigns.mode == :quick_tags, do: socket.assigns.hide_dropdown, else: true)
      )
      |> client_select(%{
        parent_event: socket.assigns[:"phx-blur"],
        current_text:
          case socket.assigns do
            %{mode: :single, selection: [option | _]} -> option[:selected_label] || option.label
            _ -> ""
          end
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("self_blur", _params, socket) do
    {:noreply, assign(socket, :hide_dropdown, true)}
  end

  @impl true
  def handle_event(event, _params, socket) when event in ~w(focus click) do
    keep_label_on_select =
      socket.assigns.keep_label_on_select &&
        socket.assigns.mode == :single &&
        socket.assigns.selection != []

    display_text =
      if keep_label_on_select do
        option = hd(socket.assigns.selection)
        option[:selected_label] || option.label
      else
        socket.assigns.current_text
      end

    socket =
      socket
      |> assign(current_text: if(keep_label_on_select, do: "", else: socket.assigns.current_text))
      |> client_select(%{
        input_event: false,
        parent_event: socket.assigns[:"phx-focus"],
        current_text: display_text
      })
      |> assign(hide_dropdown: false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change", %{"text" => text}, socket) do
    socket =
      socket
      |> assign(hide_dropdown: false, current_text: text, awaiting_update: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("selection_recovery", selection_from_client, socket) do
    options =
      for %{"label" => _label, "value" => _value} = option <- selection_from_client do
        option
        |> Map.take(~w(label value selected_label tag_label sticky disabled))
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
      end

    json = Phoenix.json_library()

    {:noreply,
     assign(socket,
       options: options,
       selection:
         Enum.map(socket.assigns.selection, fn %{value: value} ->
           Enum.find(options, fn %{value: option_value} ->
             json.encode!(option_value) == json.encode!(value)
           end)
         end)
         |> Enum.filter(& &1)
     )}
  end

  @impl true
  def handle_event("options_clear", _params, socket), do: {:noreply, clear_options(socket)}

  @impl true
  def handle_event("keydown", %{"key" => key} = params, socket)
      when key in ["ArrowDown", "ArrowUp"] do
    assigns = socket.assigns

    active_option =
      if assigns.mode != :quick_tags && assigns.max_selectable > 0 &&
           length(assigns.selection) >= assigns.max_selectable do
        assigns.active_option
      else
        visual_order =
          Map.get_lazy(params, "visual_order", fn ->
            Enum.to_list(0..(length(assigns.options) - 1)//1)
          end)

        selectable = selectable_in_visual_order(assigns, visual_order)
        selectable = if key == "ArrowUp", do: Enum.reverse(selectable), else: selectable

        case assigns.active_option do
          -1 ->
            List.first(selectable, -1)

          current ->
            case Enum.drop_while(selectable, &(&1 != current)) do
              [_, next | _] -> next
              [^current] -> current
              [] -> List.first(selectable, -1)
            end
        end
      end

    socket =
      assign(socket,
        active_option: active_option,
        hide_dropdown: false
      )
      |> push_event("scroll_to_option", %{id: assigns.id, idx: active_option})

    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => "Enter"} = params, socket) do
    visual_order =
      Map.get_lazy(params, "visual_order", fn ->
        Enum.to_list(0..(length(socket.assigns.options) - 1)//1)
      end)

    {:noreply, select_on_enter(socket, visual_order)}
  end

  @impl true
  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    socket =
      socket
      |> assign(:hide_dropdown, true)
      |> client_select(%{
        current_text:
          case socket.assigns do
            %{mode: :single, selection: [option | _]} -> option[:selected_label] || option.label
            _ -> nil
          end
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("option_click", %{"idx" => idx}, socket) do
    idx = String.to_integer(idx)

    socket =
      if idx >= 0 && idx < length(socket.assigns.options) do
        socket
        |> assign(:active_option, idx)
        |> maybe_select()
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("option_remove", %{"idx" => idx}, socket) do
    {:noreply, unselect(socket, String.to_integer(idx))}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(selection: [], current_text: "")
      |> client_select(%{input_event: true, current_text: ""})

    {:noreply, socket}
  end

  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  defp select_on_enter(%{assigns: %{awaiting_update: true}} = socket, _visual_order) do
    assign(socket, :pending_enter, true)
  end

  defp select_on_enter(socket, visual_order) do
    socket =
      if socket.assigns.dropdown_selectable_priority &&
           !socket.assigns.hide_dropdown &&
           socket.assigns.active_option == -1 do
        case selectable_in_visual_order(socket.assigns, visual_order) do
          [first_selectable | _] -> assign(socket, :active_option, first_selectable)
          [] -> socket
        end
      else
        socket
      end

    socket
    |> assign(:pending_enter, false)
    |> maybe_select()
  end

  defp maybe_select(
         %{
           assigns: %{
             current_text: current_text,
             user_defined_options: true,
             awaiting_update: false,
             active_option: -1
           }
         } = socket
       )
       when current_text != "" do
    {:ok, option} = normalize_option(current_text)

    if Enum.any?(socket.assigns.selection, &(&1.label == option.label)) do
      socket
    else
      select(socket, option)
    end
  end

  defp maybe_select(
         %{assigns: %{options: [option], selection: selection, active_option: -1}} = socket
       ) do
    if Enum.any?(selection, &(&1.label == option.label)) do
      socket
    else
      select(socket, option)
    end
  end

  defp maybe_select(%{assigns: %{active_option: -1}} = socket), do: socket

  defp maybe_select(
         %{assigns: %{active_option: active_option, options: options, selection: selection}} =
           socket
       )
       when active_option >= 0 do
    option = Enum.at(options, active_option)

    if Enum.any?(selection, &(&1.label == option.label)) do
      pos = Enum.find_index(selection, &(&1.label == option.label))
      unselect(socket, pos)
    else
      select(socket, option)
    end
  end

  defp select(socket, %{disabled: true}) do
    socket
  end

  defp select(
         %{assigns: %{selection: selection, max_selectable: max_selectable}} = socket,
         _selected
       )
       when max_selectable > 0 and length(selection) >= max_selectable do
    socket
  end

  defp select(socket, selected) do
    selection =
      if socket.assigns.mode in [:tags, :quick_tags] do
        socket.assigns.selection ++ [selected]
      else
        [selected]
      end

    socket =
      socket
      |> assign(
        active_option:
          if(socket.assigns.mode == :quick_tags, do: socket.assigns.active_option, else: -1),
        selection: selection,
        hide_dropdown: socket.assigns.mode != :quick_tags
      )
      |> then(
        &if &1.assigns.keep_options_on_select || &1.assigns.mode == :quick_tags do
          &1
        else
          clear_options(&1)
        end
      )

    client_select(socket, %{
      input_event: true,
      parent_event: if(socket.assigns.mode == :single, do: socket.assigns[:"phx-blur"]),
      current_text:
        case socket.assigns do
          %{mode: :single, selection: [option | _]} ->
            option[:selected_label] || option.label

          %{keep_options_on_select: true, current_text: text} ->
            text

          %{mode: :quick_tags, current_text: text} ->
            text

          _ ->
            ""
        end
    })
    |> push_event("scroll_to_option", %{id: socket.assigns.id, idx: socket.assigns.active_option})
  end

  defp unselect(socket, pos) do
    if Enum.at(socket.assigns.selection, pos)[:sticky] do
      socket
    else
      socket
      |> update(:selection, &List.delete_at(&1, pos))
      |> client_select(%{input_event: true})
      |> push_event("scroll_to_option", %{
        id: socket.assigns.id,
        idx: socket.assigns.active_option
      })
    end
  end

  defp clear_options(socket) do
    assign(socket,
      active_option: -1,
      awaiting_update: false,
      current_text: "",
      options: [],
      pending_enter: false
    )
  end

  defp client_select(socket, extra_params) do
    socket
    |> push_event(
      "select",
      %{
        id: socket.assigns.id,
        mode: socket.assigns.mode,
        selection: socket.assigns.selection
      }
      |> Map.merge(extra_params)
    )
  end

  defp update_selection(value, current_selection, options, :single, value_mapper)
       when not is_nil(value) do
    List.wrap(normalize_selection_value(value, options ++ current_selection, value_mapper))
  end

  defp update_selection(value, current_selection, options, _mode, value_mapper)
       when not is_nil(value) do
    value = if Enumerable.impl_for(value), do: value, else: [value]

    Enum.map(value, &normalize_selection_value(&1, options ++ current_selection, value_mapper))
    |> Enum.reject(&is_nil/1)
  end

  defp update_selection(nil, _current_selection, _options, _mode, _value_mapper), do: []

  defp normalize_selection_value(%Ecto.Changeset{action: :replace}, _options, _value_mapper),
    do: nil

  defp normalize_selection_value(%Ecto.Changeset{} = changeset, options, value_mapper) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> normalize_selection_value(options, value_mapper)
  end

  defp normalize_selection_value(selection_value, options, value_mapper) do
    selection_value = value_mapper.(selection_value)

    if option = Enum.find(options, fn %{value: value} -> selection_value == value end) do
      option
    else
      case normalize_option(selection_value) do
        {:ok, option} -> option
        :error -> %{label: "", value: selection_value}
      end
    end
  end

  defp normalize_options(options) when is_map(options) do
    normalize_options(Enum.sort(options))
  end

  defp normalize_options(options) do
    options
    |> Enum.map(
      &case normalize_option(&1) do
        {:ok, option} ->
          option

        :error ->
          raise """
          invalid element in options: #{inspect(&1)}
          elements can be:

          atoms, strings, or numbers
          maps or keywords with keys: (:label, :value) or (:key, :value) and optional keys :selected_label or :tag_label
          2-element or 3-element tuples
          """
      end
    )
  end

  defp normalize_option(option) when is_list(option) do
    if Keyword.keyword?(option) do
      Map.new(option)
      |> normalize_option()
    else
      :error
    end
  end

  defp normalize_option(option) when is_map(option) do
    case option do
      %{key: key, value: _value} = option ->
        {:ok, Enum.into(option, %{label: key, disabled: false})}

      %{value: value} = option ->
        {:ok, Enum.into(option, %{label: value, disabled: false})}

      _ ->
        :error
    end
  end

  defp normalize_option(option) when is_tuple(option) do
    case option do
      {label, value} ->
        {:ok, %{label: label, value: value, disabled: false}}

      {label, value, disabled} ->
        {:ok, %{label: label, value: value, disabled: disabled}}

      _ ->
        :error
    end
  end

  defp normalize_option(option) do
    case option do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      option when is_binary(option) or is_atom(option) or is_number(option) ->
        {:ok, %{label: option, value: option, disabled: false}}

      _ ->
        :error
    end
  end

  defp class(style, element, class_override, class_extend \\ nil)

  defp class(_style, _element, class_override, nil) when is_list(class_override) do
    class_override
  end

  defp class(style, element, nil, nil) do
    get_in(@styles, [style, element]) |> List.wrap()
  end

  defp class(_style, _element, class_override, nil) do
    String.split(class_override)
  end

  defp class(:none, element, nil, _class_extend) do
    raise """
    When using `style: :none`, please use only `#{element}_class` and not `#{element}_extra_class`
    """
  end

  defp class(style, element, nil, class_extend) when is_list(class_extend) do
    extend(
      get_in(@styles, [style, element]) |> List.wrap(),
      class_extend
    )
  end

  defp class(style, element, nil, class_extend) do
    class(style, element, nil, String.split(class_extend))
  end

  defp class(_style, element, _class_override, _class_extend) do
    raise """
    You specified both `#{element}_class` and `#{element}_extra_class` options.
    The `#{element}_class` and `#{element}_extra_class` options can't be used together.
    Use `#{element}_class` if you want to completely override the default class for `#{element}`.
    Use `#{element}_extra_class` if you want to extend the default class for the element with additional classes.
    """
  end

  defp selectable_in_visual_order(
         %{options: options, selection: selection, mode: mode},
         visual_order
       ) do
    Enum.filter(visual_order, fn idx ->
      option = Enum.at(options, idx)

      if option && not Map.get(option, :disabled, false) do
        selected = Enum.find(selection, &(&1.label == option.label))

        !selected || (mode == :quick_tags && !selected[:sticky])
      end
    end)
  end
end
