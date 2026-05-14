defmodule ToreWeb.DealsLive do
  use ToreWeb, :live_view

  alias Tore.{Deals, Handlers.DealsHandler}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       deals: Deals.list_current(),
       store_configs: Deals.list_store_configs(),
       scrape_url: "",
       scrape_chain: "ica",
       scraping: false,
       show_add_store: false
     )}
  end

  @impl true
  def handle_event("scrape_url", %{"url" => url, "chain" => chain}, socket) do
    chain_atom = String.to_existing_atom(chain)
    pid = self()

    Task.start(fn ->
      result = DealsHandler.scrape_url(url, chain_atom)
      send(pid, {:scrape_result, result})
    end)

    {:noreply, assign(socket, scraping: true)}
  end

  @impl true
  def handle_event("scrape_all", _params, socket) do
    pid = self()

    Task.start(fn ->
      DealsHandler.scrape_all()
      send(pid, {:scrape_all_done})
    end)

    {:noreply, assign(socket, scraping: true)}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    config = Deals.get_store_config!(String.to_integer(id))

    case Deals.update_store_config(config, %{scrape_enabled: !config.scrape_enabled}) do
      {:ok, _} ->
        {:noreply, assign(socket, store_configs: Deals.list_store_configs())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update store"))}
    end
  end

  @impl true
  def handle_event("delete_store", %{"id" => id}, socket) do
    config = Deals.get_store_config!(String.to_integer(id))

    case Deals.delete_store_config(config) do
      {:ok, _} ->
        {:noreply, assign(socket, store_configs: Deals.list_store_configs())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete store"))}
    end
  end

  @impl true
  def handle_event("show_add_store", _params, socket) do
    {:noreply, assign(socket, show_add_store: true)}
  end

  @impl true
  def handle_event("cancel_add_store", _params, socket) do
    {:noreply, assign(socket, show_add_store: false)}
  end

  @impl true
  def handle_event("add_store", %{"name" => name, "chain" => chain, "url" => url}, socket) do
    attrs = %{name: name, chain: String.to_existing_atom(chain), url: nilify(url), scrape_enabled: true}

    case Deals.create_store_config(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(store_configs: Deals.list_store_configs(), show_add_store: false)
         |> put_flash(:info, gettext("Store added"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add store"))}
    end
  end

  @impl true
  def handle_info({:scrape_result, {:ok, count}}, socket) do
    {:noreply,
     socket
     |> assign(scraping: false, deals: Deals.list_current())
     |> put_flash(:info, gettext("Imported %{count} deals", count: count))}
  end

  @impl true
  def handle_info({:scrape_result, {:error, _}}, socket) do
    {:noreply,
     socket
     |> assign(scraping: false)
     |> put_flash(:error, gettext("Scrape failed"))}
  end

  @impl true
  def handle_info({:scrape_all_done}, socket) do
    {:noreply,
     socket
     |> assign(scraping: false, deals: Deals.list_current())
     |> put_flash(:info, gettext("Scrape complete"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/deals"}>
    <.page max_width={:md}>

      <%!-- ── Admin: store config management ────────────────────────── --%>
      <%= if @current_user && @current_user.role == :admin do %>
        <.card padded={false} class="mb-4">
          <header class="px-6 pt-6 pb-3 flex items-center justify-between">
            <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">{gettext("Stores")}</h2>
            <div class="flex items-center gap-2">
              <%= if @scraping do %>
                <span class="text-[color:var(--muted)] inline-flex items-center gap-1.5" style="font-size: var(--t-meta);">
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" /> {gettext("Scraping…")}
                </span>
              <% else %>
                <.button phx-click="scrape_all" variant={:ghost} size={:md}>{gettext("Scrape all")}</.button>
              <% end %>
              <.button phx-click="show_add_store" variant={:ghost} size={:md}>
                <.icon name="hero-plus" class="size-4" />
              </.button>
            </div>
          </header>

          <%= if @show_add_store do %>
            <form phx-submit="add_store" class="px-6 pb-4 pt-2 border-t border-[color:var(--hairline)] space-y-3">
              <h3 class="font-medium text-[var(--text)]" style="font-size: var(--t-body);">{gettext("Add store")}</h3>
              <div class="grid grid-cols-2 gap-3">
                <.field name="name" label={gettext("Name")} placeholder="ICA Maxi Hemköp" required />
                <div>
                  <label class="block mb-1 text-[color:var(--subtle)]" style="font-size: var(--t-meta);">{gettext("Chain")}</label>
                  <select name="chain" class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-2 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]" style="font-size: var(--t-meta);">
                    <option value="ica">ICA</option>
                    <option value="coop">Coop</option>
                  </select>
                </div>
              </div>
              <.field name="url" label={gettext("Deals URL")} placeholder="https://www.ica.se/erbjudanden/..." />
              <div class="flex gap-2">
                <.button type="submit" variant={:primary} size={:md}>{gettext("Add")}</.button>
                <.button type="button" phx-click="cancel_add_store" variant={:ghost} size={:md}>{gettext("Cancel")}</.button>
              </div>
            </form>
          <% end %>

          <%= if @store_configs == [] do %>
            <div class="px-6 py-6 border-t border-[color:var(--hairline)]">
              <.empty message={gettext("No stores configured")} />
            </div>
          <% else %>
            <ul class="border-t border-[color:var(--hairline)] divide-y divide-[color:var(--hairline)]">
              <li :for={config <- @store_configs} class="px-6 py-3 flex items-center gap-3">
                <div class="flex-1 min-w-0">
                  <p class="font-medium text-[var(--text)]" style="font-size: var(--t-body);">{config.name}</p>
                  <p class="text-[color:var(--muted)] truncate" style="font-size: var(--t-meta);">
                    <span class="uppercase tracking-wide">{config.chain}</span>
                    <%= if config.url do %>
                      <span class="ml-1">· {config.url}</span>
                    <% end %>
                  </p>
                </div>
                <button
                  phx-click="toggle_enabled"
                  phx-value-id={config.id}
                  class={[
                    "shrink-0 h-6 w-11 rounded-full transition-colors",
                    config.scrape_enabled && "bg-[color:var(--accent)]" || "bg-[color:var(--border)]"
                  ]}
                  aria-label={gettext("Toggle scraping")}
                >
                  <span class={[
                    "block h-5 w-5 rounded-full bg-white shadow transition-transform mx-0.5",
                    config.scrape_enabled && "translate-x-5" || "translate-x-0"
                  ]} />
                </button>
                <button
                  phx-click="delete_store"
                  phx-value-id={config.id}
                  class="size-8 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]"
                  aria-label={gettext("Delete")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </li>
            </ul>
          <% end %>

          <%!-- ── One-shot scrape ───────────────────────────────────── --%>
          <div class="px-6 py-4 border-t border-[color:var(--hairline)]">
            <p class="text-[color:var(--subtle)] mb-2" style="font-size: var(--t-meta);">{gettext("Scrape a custom URL once")}</p>
            <form phx-submit="scrape_url" class="flex gap-2 items-end">
              <div class="flex-1">
                <.field name="url" label={gettext("URL")} placeholder="https://www.ica.se/erbjudanden/..." required />
              </div>
              <div class="shrink-0">
                <label class="block mb-1 text-[color:var(--subtle)]" style="font-size: var(--t-meta);">{gettext("Chain")}</label>
                <select name="chain" class="rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-2 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]" style="font-size: var(--t-meta);">
                  <option value="ica">ICA</option>
                  <option value="coop">Coop</option>
                </select>
              </div>
              <.button type="submit" variant={:primary} size={:md} disabled={@scraping}>{gettext("Scrape")}</.button>
            </form>
          </div>
        </.card>
      <% end %>

      <%!-- ── Deals list ────────────────────────────────────────────── --%>
      <.card padded={false}>
        <header class="px-6 pt-6 pb-3">
          <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">{gettext("Current deals")}</h1>
        </header>

        <%= if @deals == [] do %>
          <div class="px-6 py-8 border-t border-[color:var(--hairline)]">
            <.empty message={gettext("No current deals")} />
          </div>
        <% else %>
          <ul class="border-t border-[color:var(--hairline)] divide-y divide-[color:var(--hairline)]">
            <li :for={deal <- @deals} class="px-6 py-3 flex items-center gap-3">
              <div class="flex-1 min-w-0">
                <p class="font-medium text-[var(--text)]" style="font-size: var(--t-body);">{deal.product_name}</p>
                <p :if={deal.brand || deal.offer_condition} class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                  <span :if={deal.brand}>{deal.brand}</span>
                  <span :if={deal.brand && deal.offer_condition}> · </span>
                  <span :if={deal.offer_condition}>{deal.offer_condition}</span>
                </p>
              </div>
              <div :if={deal.price} class="shrink-0 text-right">
                <span class="font-semibold text-[color:var(--accent)]" style="font-size: var(--t-body);">{deal.price} kr</span>
                <span :if={deal.price_unit} class="ml-0.5 text-[color:var(--muted)]" style="font-size: var(--t-meta);">/{deal.price_unit}</span>
              </div>
            </li>
          </ul>
        <% end %>
      </.card>
    </.page>
    </Layouts.app>
    """
  end

  defp nilify(""), do: nil
  defp nilify(v), do: v
end
