defmodule ScullionWeb.GroceryLive do
  use ScullionWeb, :live_view

  alias Scullion.Handlers.GroceriesHandler
  alias Phoenix.PubSub

  def mount(_params, session, socket) do
    week_start = week_start(Date.utc_today())
    list_id = grocery_id(week_start)

    if connected?(socket) do
      PubSub.subscribe(Scullion.PubSub, "grocery_list")
    end

    {:ok, grocery_state} = GroceriesHandler.load_list(list_id)
    user_id = Map.get(session, "user_id")

    {:ok,
     assign(socket,
       week_start: week_start,
       list_id: list_id,
       grocery_state: grocery_state,
       user_id: user_id
     )}
  end

  def handle_event("check_item", %{"item_id" => id}, socket) do
    GroceriesHandler.check_item(socket.assigns.list_id, id, socket.assigns.user_id)
    {:noreply, socket}
  end

  def handle_event("uncheck_item", %{"item_id" => id}, socket) do
    GroceriesHandler.uncheck_item(socket.assigns.list_id, id, socket.assigns.user_id)
    {:noreply, socket}
  end

  def handle_event("remove_item", %{"item_id" => id}, socket) do
    GroceriesHandler.remove_item(socket.assigns.list_id, id, socket.assigns.user_id)
    {:noreply, socket}
  end

  def handle_event("add_item", %{"name" => name, "quantity" => qty, "unit" => unit}, socket) do
    quantity = if qty == "", do: nil, else: Decimal.new(qty)
    unit = if unit == "", do: nil, else: unit
    GroceriesHandler.add_item(socket.assigns.list_id, name, quantity, unit, socket.assigns.user_id)
    {:noreply, socket}
  end

  def handle_info({:events, _events}, socket) do
    {:ok, grocery_state} = GroceriesHandler.load_list(socket.assigns.list_id)
    {:noreply, assign(socket, grocery_state: grocery_state)}
  end

  def render(assigns) do
    assigns = assign(assigns, items: sorted_items(assigns.grocery_state.items))

    ~H"""
    <div class="max-w-lg mx-auto p-4">
      <h1 class="text-xl font-semibold mb-1">Grocery List</h1>
      <div class="text-sm text-gray-500 mb-4">Week of <%= Date.to_iso8601(@week_start) %></div>

      <%= if @items == [] do %>
        <div class="text-gray-400 text-sm py-8 text-center">
          No items — assign recipes in the planner and tap Build Grocery List.
        </div>
      <% else %>
        <ul class="divide-y">
          <%= for item <- @items do %>
            <li class={["flex items-center gap-3 py-3", item.checked && "opacity-50"]}>
              <button
                phx-click={if item.checked, do: "uncheck_item", else: "check_item"}
                phx-value-item_id={item.id}
                class="flex-shrink-0"
              >
                <div class={[
                  "w-5 h-5 rounded border-2 flex items-center justify-center",
                  item.checked && "bg-green-500 border-green-500 text-white",
                  !item.checked && "border-gray-300"
                ]}>
                  <%= if item.checked, do: "✓" %>
                </div>
              </button>
              <span class={["flex-1 text-sm", item.checked && "line-through"]}>
                <%= item.name %>
              </span>
              <span class="text-xs text-gray-400">
                <%= format_quantity(item.quantity, item.unit) %>
              </span>
              <button
                phx-click="remove_item"
                phx-value-item_id={item.id}
                class="text-gray-300 hover:text-red-400 text-xs"
              >
                ✕
              </button>
            </li>
          <% end %>
        </ul>
      <% end %>

      <form phx-submit="add_item" class="mt-6 flex flex-col gap-2">
        <div class="text-sm font-medium text-gray-600">Add item</div>
        <input
          type="text"
          name="name"
          placeholder="Name"
          required
          class="border rounded px-3 py-2 text-sm w-full"
        />
        <div class="flex gap-2">
          <input
            type="text"
            name="quantity"
            placeholder="Qty"
            class="border rounded px-3 py-2 text-sm w-24"
          />
          <input
            type="text"
            name="unit"
            placeholder="Unit"
            class="border rounded px-3 py-2 text-sm flex-1"
          />
        </div>
        <button type="submit" class="bg-blue-600 text-white rounded py-2 text-sm">
          Add
        </button>
      </form>
    </div>
    """
  end

  defp sorted_items(items) do
    items
    |> Map.values()
    |> Enum.sort_by(fn i -> {i.checked, i.name} end)
  end

  defp format_quantity(nil, nil), do: ""
  defp format_quantity(nil, unit), do: unit
  defp format_quantity(qty, nil), do: Decimal.to_string(qty)
  defp format_quantity(qty, unit), do: "#{Decimal.to_string(qty)} #{unit}"

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp grocery_id(week_start), do: "grocery_list:#{Date.to_iso8601(week_start)}"
end
