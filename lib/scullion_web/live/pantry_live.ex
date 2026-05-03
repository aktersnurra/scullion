defmodule ScullionWeb.PantryLive do
  use ScullionWeb, :live_view

  alias Scullion.Pantry

  def mount(_params, _session, socket) do
    {:ok, assign(socket, items: Pantry.list_inventory())}
  end

  def handle_event("add_item", params, socket) do
    attrs = %{
      name: params["name"],
      quantity: parse_decimal(params["quantity"]),
      unit: nilify(params["unit"]),
      category: nilify(params["category"]),
      expires_at: parse_date(params["expires_at"])
    }

    case Pantry.add_item(attrs) do
      {:ok, _} -> {:noreply, assign(socket, items: Pantry.list_inventory())}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to add item")}
    end
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    Pantry.remove_item(String.to_integer(id))
    {:noreply, assign(socket, items: Pantry.list_inventory())}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-xl font-semibold text-gray-900 mb-5">Pantry</h1>

      <div class="bg-white rounded-2xl border border-gray-100 overflow-hidden mb-5">
        <%= if @items == [] do %>
          <p class="text-gray-400 text-sm py-12 text-center">Nothing in pantry</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs text-gray-400 border-b border-gray-50">
                <th class="px-4 py-3 font-medium">Item</th>
                <th class="px-4 py-3 font-medium">Qty</th>
                <th class="px-4 py-3 font-medium">Category</th>
                <th class="px-4 py-3 font-medium">Expires</th>
                <th></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-50">
              <%= for item <- @items do %>
                <tr class={expiry_class(item.expires_at)}>
                  <td class="px-4 py-3 font-medium text-gray-800"><%= item.name %></td>
                  <td class="px-4 py-3 text-gray-500"><%= format_qty(item.quantity, item.unit) %></td>
                  <td class="px-4 py-3 text-gray-400"><%= item.category %></td>
                  <td class="px-4 py-3 text-gray-400"><%= format_date(item.expires_at) %></td>
                  <td class="px-4 py-3 text-right">
                    <%= if @current_user && @current_user.role in [:member, :admin] do %>
                      <button phx-click="remove_item" phx-value-id={item.id}
                              class="text-gray-200 hover:text-red-400 text-sm">✕</button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <%= if @current_user && @current_user.role in [:member, :admin] do %>
        <form phx-submit="add_item" class="bg-white rounded-2xl border border-gray-100 p-4 space-y-2">
          <div class="text-sm font-medium text-gray-600">+ Add to pantry</div>
          <div class="flex gap-2">
            <input type="text" name="name" placeholder="Item name" required
                   class="border border-gray-200 rounded-lg px-3 py-2 text-sm flex-1 focus:outline-none focus:ring-2 focus:ring-green-500" />
            <input type="text" name="quantity" placeholder="Qty"
                   class="border border-gray-200 rounded-lg px-3 py-2 text-sm w-20 focus:outline-none focus:ring-2 focus:ring-green-500" />
            <input type="text" name="unit" placeholder="Unit"
                   class="border border-gray-200 rounded-lg px-3 py-2 text-sm w-20 focus:outline-none focus:ring-2 focus:ring-green-500" />
          </div>
          <div class="flex gap-2">
            <input type="text" name="category" placeholder="Category (e.g. dairy)"
                   class="border border-gray-200 rounded-lg px-3 py-2 text-sm flex-1 focus:outline-none focus:ring-2 focus:ring-green-500" />
            <input type="date" name="expires_at"
                   class="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500" />
          </div>
          <button type="submit" class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium">
            Add
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp parse_decimal(""), do: nil
  defp parse_decimal(nil), do: nil
  defp parse_decimal(s), do: Decimal.new(s)

  defp nilify(""), do: nil
  defp nilify(v), do: v

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp format_qty(nil, nil), do: ""
  defp format_qty(nil, unit), do: unit
  defp format_qty(qty, nil), do: Decimal.to_string(qty)
  defp format_qty(qty, unit), do: "#{Decimal.to_string(qty)} #{unit}"

  defp format_date(nil), do: ""
  defp format_date(d), do: Date.to_iso8601(d)

  defp expiry_class(nil), do: ""

  defp expiry_class(expires_at) do
    if Date.diff(expires_at, Date.utc_today()) <= 3, do: "text-red-600", else: ""
  end
end
