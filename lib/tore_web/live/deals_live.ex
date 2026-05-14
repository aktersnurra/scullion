defmodule ToreWeb.DealsLive do
  use ToreWeb, :live_view

  alias Tore.{Deals, Handlers.DealsHandler}

  def mount(_params, _session, socket) do
    deals = Deals.list_current()
    {:ok, assign(socket, deals: deals, url: "", chain: "ica")}
  end

  def handle_event("scrape_url", %{"url" => url, "chain" => chain}, socket) do
    chain_atom = String.to_existing_atom(chain)

    case DealsHandler.scrape_url(url, chain_atom) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(deals: Deals.list_current())
         |> put_flash(:info, gettext("Imported %{count} deals", count: count))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Scrape failed"))}
    end
  end

  def handle_event("scrape_all", _params, socket) do
    DealsHandler.scrape_all()

    {:noreply,
     socket
     |> assign(deals: Deals.list_current())
     |> put_flash(:info, gettext("Scrape triggered"))}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-4">
      <h1 class="text-xl font-semibold mb-4">{gettext("Current Deals")}</h1>

      <%= if @current_user && @current_user.role == :admin do %>
        <div class="mb-6 flex gap-2">
          <input
            type="text"
            name="url"
            placeholder={gettext("https://www.ica.se/erbjudanden/...")}
            class="flex-1 border rounded px-2 py-1 text-sm"
          />
          <select name="chain" class="border rounded px-2 py-1 text-sm">
            <option value="ica">{gettext("ICA")}</option>
            <option value="coop">{gettext("Coop")}</option>
          </select>
          <button
            phx-click="scrape_all"
            class="px-3 py-1 bg-indigo-600 text-white rounded text-sm"
          >
            {gettext("Scrape All")}
          </button>
        </div>
      <% end %>

      <%= if Enum.empty?(@deals) do %>
        <p class="text-gray-500 text-sm">{gettext("No current deals.")}</p>
      <% else %>
        <ul class="divide-y">
          <%= for deal <- @deals do %>
            <li class="py-2">
              <span class="font-medium"><%= deal.product_name %></span>
              <%= if deal.brand do %>
                <span class="text-gray-500 text-sm ml-1"><%= deal.brand %></span>
              <% end %>
              <%= if deal.price do %>
                <span class="ml-2 text-green-700 font-semibold"><%= deal.price %> kr</span>
                <%= if deal.price_unit do %>
                  <span class="text-xs text-gray-500"><%= deal.price_unit %></span>
                <% end %>
              <% end %>
              <%= if deal.offer_condition do %>
                <span class="ml-2 text-xs text-gray-400"><%= deal.offer_condition %></span>
              <% end %>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end
end
