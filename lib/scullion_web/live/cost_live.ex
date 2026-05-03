defmodule ScullionWeb.CostLive do
  use ScullionWeb, :live_view

  alias Scullion.Costs

  def mount(_params, _session, socket) do
    today = Date.utc_today()
    {:ok, summary} = Costs.monthly_summary(today.year, today.month)

    {:ok,
     assign(socket,
       view: :overview,
       summary: summary,
       receipts: [],
       dining_entries: []
     )}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    socket = load_tab(socket, tab)
    {:noreply, assign(socket, view: tab)}
  end

  def handle_event("log_dining_out", params, socket) do
    user_id = socket.assigns.current_user.id

    attrs = %{
      date: Date.from_iso8601!(params["date"]),
      description: params["description"],
      total_amount: Decimal.new(params["total_amount"]),
      num_people: String.to_integer(params["num_people"] || "1"),
      user_id: user_id
    }

    case Costs.log_dining_out(attrs) do
      {:ok, _} ->
        today = Date.utc_today()
        {:ok, summary} = Costs.monthly_summary(today.year, today.month)
        {:noreply, socket |> assign(summary: summary) |> put_flash(:info, "Logged")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to log")}
    end
  end

  def handle_event("save_manual_receipt", params, socket) do
    user_id = socket.assigns.current_user.id

    attrs = %{
      date: Date.from_iso8601!(params["date"]),
      store_name: params["store_name"],
      total_amount: Decimal.new(params["total_amount"]),
      user_id: user_id,
      line_items: []
    }

    case Costs.log_receipt(attrs) do
      {:ok, _} ->
        today = Date.utc_today()
        {:ok, summary} = Costs.monthly_summary(today.year, today.month)
        {:noreply, socket |> assign(summary: summary) |> put_flash(:info, "Receipt saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  defp load_tab(socket, :overview) do
    today = Date.utc_today()
    {:ok, summary} = Costs.monthly_summary(today.year, today.month)
    assign(socket, summary: summary)
  end

  defp load_tab(socket, _), do: socket

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-xl font-semibold text-gray-900 mb-5">Costs</h1>

      <div class="flex gap-1 mb-6 bg-gray-100 rounded-xl p-1 w-fit">
        <%= for {tab, label} <- [overview: "Overview", receipts: "Receipts", dining: "Dining Out"] do %>
          <button phx-click="switch_tab" phx-value-tab={tab}
                  class={["px-4 py-1.5 rounded-lg text-sm transition-colors",
                    if(@view == tab, do: "bg-white shadow-sm text-gray-900 font-medium", else: "text-gray-500 hover:text-gray-700")]}>
            <%= label %>
          </button>
        <% end %>
      </div>

      <%= if @view == :overview do %>
        <div class="grid grid-cols-3 gap-4">
          <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
            <div class="text-xs text-gray-400 mb-1">Groceries</div>
            <div class="text-xl font-semibold text-gray-900"><%= @summary.grocery_total %> kr</div>
            <div class="text-xs text-gray-400 mt-1"><%= @summary.receipt_count %> receipts</div>
          </div>
          <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
            <div class="text-xs text-gray-400 mb-1">Dining Out</div>
            <div class="text-xl font-semibold text-gray-900"><%= @summary.dining_total %> kr</div>
            <div class="text-xs text-gray-400 mt-1"><%= @summary.dining_count %> entries</div>
          </div>
          <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
            <div class="text-xs text-gray-400 mb-1">Total</div>
            <div class="text-xl font-semibold text-gray-900"><%= @summary.total %> kr</div>
          </div>
        </div>
      <% end %>

      <%= if @view == :receipts do %>
        <%= if @current_user && @current_user.role in [:member, :admin] do %>
          <form phx-submit="save_manual_receipt" class="bg-white rounded-2xl border border-gray-100 p-4 mb-4 space-y-3">
            <h2 class="text-sm font-medium text-gray-700">Log Receipt</h2>
            <div class="flex gap-2">
              <input type="date" name="date" required value={Date.to_iso8601(Date.utc_today())}
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm flex-1 focus:outline-none focus:ring-2 focus:ring-green-500" />
              <input type="text" name="store_name" placeholder="Store"
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm flex-1 focus:outline-none focus:ring-2 focus:ring-green-500" />
              <input type="number" name="total_amount" placeholder="Total (kr)" step="0.01" required
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm w-28 focus:outline-none focus:ring-2 focus:ring-green-500" />
            </div>
            <button type="submit" class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium">
              Save
            </button>
          </form>
        <% end %>
        <p class="text-sm text-gray-400">No receipts loaded.</p>
      <% end %>

      <%= if @view == :dining do %>
        <%= if @current_user && @current_user.role in [:member, :admin] do %>
          <form phx-submit="log_dining_out" class="bg-white rounded-2xl border border-gray-100 p-4 mb-4 space-y-3">
            <h2 class="text-sm font-medium text-gray-700">Log Dining Out</h2>
            <div class="flex gap-2 flex-wrap">
              <input type="date" name="date" required value={Date.to_iso8601(Date.utc_today())}
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-green-500" />
              <input type="text" name="description" placeholder="Restaurant / occasion"
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm flex-1 focus:outline-none focus:ring-2 focus:ring-green-500" />
              <input type="number" name="total_amount" placeholder="Total (kr)" step="0.01" required
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm w-28 focus:outline-none focus:ring-2 focus:ring-green-500" />
              <input type="number" name="num_people" placeholder="People" min="1" value="1"
                     class="border border-gray-200 rounded-lg px-2 py-1.5 text-sm w-20 focus:outline-none focus:ring-2 focus:ring-green-500" />
            </div>
            <button type="submit" class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium">
              Log
            </button>
          </form>
        <% end %>
        <p class="text-sm text-gray-400">Dining entries will appear here.</p>
      <% end %>
    </div>
    """
  end
end
