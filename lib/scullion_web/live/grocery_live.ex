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
       user_id: user_id,
       export_text: nil
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

  def handle_event("export_list", _params, socket) do
    case GroceriesHandler.export_list(socket.assigns.list_id) do
      {:ok, text} -> {:noreply, assign(socket, export_text: text)}
      _ -> {:noreply, socket}
    end
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
    <div class="max-w-lg mx-auto p-6">
      <div class="flex items-center justify-between mb-1">
        <h1 class="text-xl font-semibold text-gray-900">Groceries</h1>
        <button phx-click="export_list" class="text-xs text-gray-400 hover:text-gray-600">
          Export for SMS
        </button>
      </div>
      <div class="text-sm text-gray-400 mb-5">
        Week of <%= Calendar.strftime(@week_start, "%B %-d") %>
      </div>

      <%= if @export_text do %>
        <textarea readonly class="mb-4 w-full border border-gray-200 rounded-xl p-3 text-sm font-mono h-28 bg-gray-50"><%= @export_text %></textarea>
      <% end %>

      <div class="bg-white rounded-2xl border border-gray-100 overflow-hidden mb-5">
        <%= if @items == [] do %>
          <div class="text-gray-400 text-sm py-12 text-center px-6">
            No items — assign recipes in the planner and tap Grocery List.
          </div>
        <% else %>
          <ul class="divide-y divide-gray-50">
            <%= for item <- @items do %>
              <li class={["flex items-center gap-3 px-4 py-3", item.checked && "opacity-60"]}>
                <button
                  phx-click={if item.checked, do: "uncheck_item", else: "check_item"}
                  phx-value-item_id={item.id}
                  class="flex-shrink-0"
                >
                  <div class={[
                    "w-5 h-5 rounded-full border-2 flex items-center justify-center text-xs font-bold",
                    item.checked && "bg-green-500 border-green-500 text-white",
                    !item.checked && "border-gray-300"
                  ]}>
                    <%= if item.checked, do: "✓" %>
                  </div>
                </button>
                <span class={["flex-1 text-sm text-gray-800", item.checked && "line-through text-gray-400"]}>
                  <%= item.name %>
                </span>
                <span class="text-xs text-gray-400 min-w-12 text-right">
                  <%= format_quantity(item.quantity, item.unit) %>
                </span>
                <button phx-click="remove_item" phx-value-item_id={item.id}
                        class="text-gray-200 hover:text-red-400 text-sm leading-none pl-1">
                  ✕
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <form phx-submit="add_item" class="bg-white rounded-2xl border border-gray-100 p-4 space-y-2">
        <div class="text-sm font-medium text-gray-600">+ Add item</div>
        <input type="text" name="name" placeholder="Item name" required
               class="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500" />
        <div class="flex gap-2">
          <input type="text" name="quantity" placeholder="Qty"
                 class="border border-gray-200 rounded-lg px-3 py-2 text-sm w-24 focus:outline-none focus:ring-2 focus:ring-green-500" />
          <input type="text" name="unit" placeholder="Unit"
                 class="border border-gray-200 rounded-lg px-3 py-2 text-sm flex-1 focus:outline-none focus:ring-2 focus:ring-green-500" />
        </div>
        <button type="submit" class="w-full bg-green-600 hover:bg-green-700 text-white rounded-lg py-2 text-sm font-medium">
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
