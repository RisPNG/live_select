defmodule LiveSelect.TestLive do
  use Phoenix.LiveView, log: false

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       form: to_form(session["source"] || %{}, as: :search),
       component: session["component"] || %{},
       owner: session["owner"],
       search_options: session["search_options"]
     )}
  end

  @impl true
  def handle_event("live_select_change", %{"id" => id} = params, socket) do
    send(socket.assigns.owner, {:search, params})

    if socket.assigns.search_options do
      send_update(LiveSelect.Component, id: id, options: socket.assigns.search_options)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("change", %{"search" => params}, socket) do
    send(socket.assigns.owner, {:form_change, params})
    {:noreply, assign(socket, :form, to_form(params, as: :search))}
  end
end
