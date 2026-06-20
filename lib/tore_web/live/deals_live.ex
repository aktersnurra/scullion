defmodule ToreWeb.DealsLive do
  use ToreWeb, :live_view

  alias Tore.Deals

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        deals: Deals.list_current(),
        store_configs: Deals.list_store_configs(),
        scraping: false,
        sources_expanded: false,
        add_modal: nil,
        collapsed_chains: MapSet.new(),
        collapsed_stores: MapSet.new(),
        editing_store: nil,
        saved_store: nil
      )
      |> allow_upload(:deals_pdf,
        accept: ~w(.pdf),
        max_entries: 1,
        max_file_size: 20_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  # ── Modal ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_add", _params, socket) do
    {:noreply, assign(socket, add_modal: %{tab: "url", url_mode: "once"})}
  end

  @impl true
  def handle_event("close_add", _params, socket) do
    {:noreply, assign(socket, add_modal: nil)}
  end

  @impl true
  def handle_event("modal_tab", %{"tab" => tab}, socket) do
    {:noreply, update(socket, :add_modal, &Map.put(&1, :tab, tab))}
  end

  @impl true
  def handle_event("url_mode", %{"mode" => mode}, socket) do
    {:noreply, update(socket, :add_modal, &Map.put(&1, :url_mode, mode))}
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  # ── Sources ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_sources", _params, socket) do
    {:noreply, update(socket, :sources_expanded, &(!&1))}
  end

  @impl true
  def handle_event("edit_store", %{"chain" => chain, "store" => store}, socket) do
    {:noreply, assign(socket, editing_store: {chain, store}, saved_store: nil)}
  end

  @impl true
  def handle_event("cancel_edit_store", _params, socket) do
    {:noreply, assign(socket, editing_store: nil)}
  end

  @impl true
  def handle_event(
        "blur_store",
        %{"value" => new_store, "chain" => chain, "old_store" => old_store},
        socket
      ) do
    new_store = String.trim(new_store)

    if new_store != "" and new_store != old_store do
      Deals.rename_store(chain, old_store, new_store)
    end

    store_key = "#{chain}:#{if new_store != "", do: new_store, else: old_store}"
    Process.send_after(self(), :clear_saved_store, 3000)

    {:noreply,
     assign(socket, editing_store: nil, saved_store: store_key, deals: Deals.list_current())}
  end

  @impl true
  def handle_event(
        "save_store",
        %{"chain" => chain, "old_store" => old_store, "store" => new_store},
        socket
      ) do
    new_store = String.trim(new_store)

    if new_store != "" and new_store != old_store do
      Deals.rename_store(chain, old_store, new_store)
    end

    store_key = "#{chain}:#{new_store}"
    Process.send_after(self(), :clear_saved_store, 3000)

    {:noreply,
     assign(socket, editing_store: nil, saved_store: store_key, deals: Deals.list_current())}
  end

  @impl true
  def handle_event("toggle_chain", %{"chain" => chain}, socket) do
    {:noreply, update(socket, :collapsed_chains, &toggle_set(&1, chain))}
  end

  @impl true
  def handle_event("toggle_store", %{"key" => key}, socket) do
    {:noreply, update(socket, :collapsed_stores, &toggle_set(&1, key))}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    config = Deals.get_store_config!(String.to_integer(id))

    case Deals.update_store_config(config, %{scrape_enabled: !config.scrape_enabled}) do
      {:ok, _} -> {:noreply, assign(socket, store_configs: Deals.list_store_configs())}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Failed to update store"))}
    end
  end

  @impl true
  def handle_event("delete_store", %{"id" => id}, socket) do
    config = Deals.get_store_config!(String.to_integer(id))

    case Deals.delete_store_config(config) do
      {:ok, _} -> {:noreply, assign(socket, store_configs: Deals.list_store_configs())}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Failed to delete store"))}
    end
  end

  # ── Add source ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("add_recurring", %{"name" => name, "url" => url} = params, socket) do
    chain = Map.get(params, "chain") || chain_from_url(url)

    attrs = %{
      name: name,
      chain: String.to_existing_atom(chain),
      url: nilify(url),
      scrape_enabled: true
    }

    case Deals.create_store_config(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(store_configs: Deals.list_store_configs(), add_modal: nil)
         |> put_flash(:info, gettext("Store added"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add store"))}
    end
  end

  @impl true
  def handle_event("scrape_once", %{"name" => name, "url" => url} = params, socket) do
    chain = Map.get(params, "chain") || chain_from_url(url)
    chain_atom = String.to_existing_atom(chain)
    store_name = nilify(name)
    pid = self()

    Task.start(fn ->
      result = Deals.scrape_url(url, chain_atom, store_name)
      send(pid, {:scrape_result, result})
    end)

    {:noreply, assign(socket, scraping: true, add_modal: nil)}
  end

  @impl true
  def handle_event("scrape_all", _params, socket) do
    pid = self()

    Task.start(fn ->
      Deals.scrape_all()
      send(pid, {:scrape_all_done})
    end)

    {:noreply, assign(socket, scraping: true)}
  end

  # ── Async results ───────────────────────────────────────────────────────

  @impl true
  def handle_info({:scrape_result, {:ok, count}}, socket) do
    {:noreply,
     socket
     |> assign(scraping: false, deals: Deals.list_current())
     |> put_flash(:info, gettext("Imported %{count} deals", count: count))}
  end

  @impl true
  def handle_info({:scrape_result, {:error, _}}, socket) do
    {:noreply, socket |> assign(scraping: false) |> put_flash(:error, gettext("Scrape failed"))}
  end

  @impl true
  def handle_info({:scrape_all_done}, socket) do
    {:noreply,
     socket
     |> assign(scraping: false, deals: Deals.list_current())
     |> put_flash(:info, gettext("Scrape complete"))}
  end

  @impl true
  def handle_info({:pdf_result, {:ok, count}}, socket) do
    {:noreply,
     socket
     |> assign(scraping: false, deals: Deals.list_current())
     |> put_flash(:info, gettext("Imported %{count} deals from PDF", count: count))}
  end

  @impl true
  def handle_info(:clear_saved_store, socket) do
    {:noreply, assign(socket, saved_store: nil)}
  end

  @impl true
  def handle_info({:pdf_result, {:error, _}}, socket) do
    {:noreply,
     socket |> assign(scraping: false) |> put_flash(:error, gettext("PDF parse failed"))}
  end

  def handle_progress(:deals_pdf, entry, socket) do
    if entry.done? do
      [{binary, _}] =
        consume_uploaded_entries(socket, :deals_pdf, fn %{path: path}, e ->
          {:ok, {File.read!(path), e}}
        end)

      pid = self()

      Task.start(fn ->
        result = Deals.parse_pdf(binary)
        send(pid, {:pdf_result, result})
      end)

      {:noreply, assign(socket, scraping: true, add_modal: nil)}
    else
      {:noreply, socket}
    end
  end

  # ── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    grouped =
      assigns.deals
      |> Enum.group_by(& &1.chain)
      |> Enum.sort_by(fn {chain, _} -> chain end)
      |> Enum.map(fn {chain, deals} ->
        stores =
          deals
          |> Enum.group_by(& &1.store)
          |> Enum.sort_by(fn {store, _} -> store end)

        {chain, stores}
      end)

    assigns = assign(assigns, grouped: grouped)

    ~H"""
    <Layouts.app flash={@flash} inbox_count={@inbox_count} current_path={assigns[:current_path] || "/deals"}>
      <.page max_width={:md}>
        <.card padded={false}>
          <header class="px-6 pt-6 pb-3 flex items-center justify-between">
            <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">
              {gettext("Erbjudanden")}
            </h1>
            <div class="flex items-center gap-1">
              <%= if @scraping do %>
                <span
                  class="text-[color:var(--muted)] inline-flex items-center gap-1.5 mr-1"
                  style="font-size: var(--t-meta);"
                >
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" /> {gettext("Hämtar…")}
                </span>
              <% end %>
              <button
                phx-click="toggle_sources"
                title={gettext("Konfigurerade källor")}
                class={[
                  "size-8 inline-flex items-center justify-center rounded-[var(--r-md)] transition-colors",
                  (@sources_expanded && "bg-[color:var(--hairline)] text-[var(--text)]") ||
                    "text-[color:var(--muted)] hover:text-[var(--text)] hover:bg-[color:var(--hairline)]"
                ]}
              >
                <.icon
                  name={if @sources_expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
                  class="size-4"
                />
              </button>
              <button
                phx-click="open_add"
                title={gettext("Lägg till källa")}
                class="size-8 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--muted)] hover:text-[var(--text)] hover:bg-[color:var(--hairline)] transition-colors"
              >
                <.icon name="hero-plus" class="size-5" />
              </button>
            </div>
          </header>

          <%!-- Configured sources (expandable) --%>
          <%= if @sources_expanded do %>
            <div class="border-t border-[color:var(--hairline)]">
              <%= if @store_configs == [] do %>
                <p class="px-6 py-4 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                  {gettext("Inga återkommande källor konfigurerade.")}
                </p>
              <% else %>
                <ul class="divide-y divide-[color:var(--hairline)]">
                  <li :for={config <- @store_configs} class="px-6 py-3 flex items-center gap-3">
                    <div class="flex-1 min-w-0">
                      <p class="font-medium text-[var(--text)]" style="font-size: var(--t-body);">
                        {config.name}
                      </p>
                      <p class="text-[color:var(--muted)] truncate" style="font-size: var(--t-meta);">
                        <span class="uppercase tracking-wide">{config.chain}</span>
                        <span :if={config.url} class="ml-1">· {config.url}</span>
                      </p>
                    </div>
                    <button
                      phx-click="toggle_enabled"
                      phx-value-id={config.id}
                      class={[
                        "shrink-0 h-6 w-11 rounded-full transition-colors",
                        (config.scrape_enabled && "bg-[color:var(--accent)]") ||
                          "bg-[color:var(--border)]"
                      ]}
                      aria-label={gettext("Växla")}
                    >
                      <span class={[
                        "block h-5 w-5 rounded-full bg-white shadow transition-transform mx-0.5",
                        (config.scrape_enabled && "translate-x-5") || "translate-x-0"
                      ]} />
                    </button>
                    <button
                      phx-click="delete_store"
                      phx-value-id={config.id}
                      class="size-8 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]"
                      aria-label={gettext("Ta bort")}
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </li>
                </ul>
                <div class="px-6 py-3 border-t border-[color:var(--hairline)]">
                  <.button phx-click="scrape_all" variant={:ghost} size={:md} disabled={@scraping}>
                    <.icon name="hero-arrow-path" class="size-4" /> {gettext("Hämta alla")}
                  </.button>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- Deals: chain → store → deals --%>
          <%= if @grouped == [] do %>
            <div class="px-6 py-14 border-t border-[color:var(--hairline)] flex flex-col items-center text-center">
              <.icon name="hero-tag" class="size-12 text-[color:var(--subtle)] mb-3" />
              <p class="text-[color:var(--muted)]" style="font-size: var(--t-body);">
                {gettext("Inga aktuella erbjudanden")}
              </p>
              <p class="mt-1 text-[color:var(--subtle)]" style="font-size: var(--t-meta);">
                {gettext("Lägg till en källa med + ovan.")}
              </p>
            </div>
          <% else %>
            <div class="border-t border-[color:var(--hairline)]">
              <%= for {chain, stores} <- @grouped do %>
                <% chain_collapsed = MapSet.member?(@collapsed_chains, chain) %>
                <% chain_total = stores |> Enum.flat_map(fn {_, d} -> d end) |> length() %>
                <div class="border-b border-[color:var(--hairline)] last:border-b-0">
                  <%!-- Chain header --%>
                  <button
                    phx-click="toggle_chain"
                    phx-value-chain={chain}
                    class="w-full px-6 py-2 flex items-center gap-2 bg-[color:var(--hairline)] hover:bg-[color:var(--hairline)] text-left"
                  >
                    <.icon
                      name={if chain_collapsed, do: "hero-chevron-right", else: "hero-chevron-down"}
                      class="size-3.5 text-[color:var(--subtle)] shrink-0"
                    />
                    <span
                      class="font-bold uppercase tracking-wide text-[var(--text)] flex-1"
                      style="font-size: var(--t-meta);"
                    >
                      {chain}
                    </span>
                    <span
                      class="inline-flex items-center rounded-full px-2 py-0.5 bg-[color:var(--accent)]/10 text-[color:var(--accent)]"
                      style="font-size: 11px; font-weight: 500;"
                    >
                      {chain_total}
                    </span>
                  </button>

                  <%= unless chain_collapsed do %>
                    <%= for {store, deals} <- stores do %>
                      <% store_key = "#{chain}:#{store}" %>
                      <% store_collapsed = MapSet.member?(@collapsed_stores, store_key) %>
                      <%!-- Store header --%>
                      <div class="flex items-center bg-[color:var(--hairline)]/40 border-t border-[color:var(--hairline)] group/store">
                        <%!-- Collapse toggle — always stable --%>
                        <button
                          phx-click="toggle_store"
                          phx-value-key={store_key}
                          class="px-6 py-2 flex items-center gap-2 shrink-0"
                        >
                          <.icon
                            name={
                              if store_collapsed, do: "hero-chevron-right", else: "hero-chevron-down"
                            }
                            class="size-3 text-[color:var(--subtle)]"
                          />
                        </button>

                        <%!-- Store name — tap to edit --%>
                        <%= if @editing_store == {chain, store} do %>
                          <form
                            phx-submit="save_store"
                            phx-value-chain={chain}
                            phx-value-old_store={store}
                            class="flex-1 flex items-center"
                          >
                            <input
                              type="text"
                              name="store"
                              value={store}
                              autofocus
                              phx-blur="blur_store"
                              phx-value-chain={chain}
                              phx-value-old_store={store}
                              phx-keydown="cancel_edit_store"
                              phx-key="Escape"
                              class="flex-1 bg-transparent focus:outline-none font-semibold py-2 border-b border-[color:var(--accent)]"
                              style="font-size: var(--t-meta); color: #4A5560; letter-spacing: -0.01em;"
                            />
                          </form>
                        <% else %>
                          <button
                            phx-click="edit_store"
                            phx-value-chain={chain}
                            phx-value-store={store}
                            class="flex-1 text-left py-2 font-semibold"
                            style="font-size: var(--t-meta); color: #4A5560;"
                          >
                            {store}
                            <%= if @saved_store == store_key do %>
                              <span
                                class="ml-2 text-[color:var(--accent)] animate-pulse"
                                style="font-size: 10px; font-weight: 400;"
                              >
                                Sparat
                              </span>
                            <% end %>
                          </button>
                        <% end %>

                        <span
                          class="px-3 shrink-0 text-[color:var(--subtle)]"
                          style="font-size: 11px;"
                        >
                          {length(deals)}
                        </span>
                      </div>

                      <%= unless store_collapsed do %>
                        <ul class="divide-y divide-[color:var(--hairline)]">
                          <li :for={deal <- deals} class="px-6 py-3 flex items-start gap-3">
                            <div class="flex-1 min-w-0">
                              <p
                                class="font-medium text-[var(--text)]"
                                style="font-size: var(--t-body);"
                              >
                                {deal.product_name}
                              </p>
                              <p
                                :if={deal.brand || deal.size}
                                class="text-[color:var(--muted)]"
                                style="font-size: var(--t-meta);"
                              >
                                <span :if={deal.brand}>{deal.brand}</span>
                                <span :if={deal.brand && deal.size}> · </span>
                                <span :if={deal.size}>{deal.size}</span>
                              </p>
                              <p
                                :if={deal.comparison_price}
                                class="text-[color:var(--subtle)]"
                                style="font-size: var(--t-meta);"
                              >
                                {deal.comparison_price}
                              </p>
                            </div>
                            <div class="shrink-0 text-right">
                              <p
                                :if={deal.offer_condition}
                                class="font-semibold text-[color:var(--accent)]"
                                style="font-size: var(--t-body);"
                              >
                                {deal.offer_condition}
                              </p>
                              <p
                                :if={deal.price}
                                class="font-semibold text-[var(--text)]"
                                style="font-size: var(--t-body);"
                              >
                                {deal.price} {deal.price_unit || "kr"}
                              </p>
                              <p
                                :if={deal.regular_price}
                                class="text-[color:var(--muted)] line-through"
                                style="font-size: var(--t-meta);"
                              >
                                {deal.regular_price} kr
                              </p>
                            </div>
                          </li>
                        </ul>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </.card>
      </.page>

      <.add_source_modal :if={@add_modal} modal={@add_modal} scraping={@scraping} uploads={@uploads} />
    </Layouts.app>
    """
  end

  # ── Add source modal ─────────────────────────────────────────────────────

  attr :modal, :map, required: true
  attr :scraping, :boolean, required: true
  attr :uploads, :map, required: true

  defp add_source_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-end md:items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/40" phx-click="close_add"></div>

      <div
        class="relative w-full md:max-w-sm"
        phx-window-keydown="close_add"
        phx-key="Escape"
      >
        <div class="bg-[var(--surface)] rounded-[var(--r-xl)] shadow-[0_8px_32px_rgba(17,24,39,0.16)] overflow-hidden">
          <header class="flex items-center justify-between px-6 py-4 border-b border-[color:var(--hairline)]">
            <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">
              {gettext("Lägg till källa")}
            </h2>
            <button
              type="button"
              phx-click="close_add"
              class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </header>

          <%!-- URL / PDF tab switcher --%>
          <div class="flex border-b border-[color:var(--hairline)]">
            <button
              phx-click="modal_tab"
              phx-value-tab="url"
              class={[
                "flex-1 py-3 text-center transition-colors",
                (@modal.tab == "url" &&
                   "text-[color:var(--accent)] border-b-2 border-[color:var(--accent)] -mb-px font-medium") ||
                  "text-[color:var(--muted)] hover:text-[var(--text)]"
              ]}
              style="font-size: var(--t-meta);"
            >
              {gettext("URL")}
            </button>
            <button
              phx-click="modal_tab"
              phx-value-tab="pdf"
              class={[
                "flex-1 py-3 text-center transition-colors",
                (@modal.tab == "pdf" &&
                   "text-[color:var(--accent)] border-b-2 border-[color:var(--accent)] -mb-px font-medium") ||
                  "text-[color:var(--muted)] hover:text-[var(--text)]"
              ]}
              style="font-size: var(--t-meta);"
            >
              {gettext("PDF")}
            </button>
          </div>

          <%!-- URL tab --%>
          <%= if @modal.tab == "url" do %>
            <div class="p-6 space-y-4">
              <%!-- Once / Recurring toggle --%>
              <div class="flex rounded-[var(--r-md)] border border-[color:var(--border)] overflow-hidden">
                <button
                  phx-click="url_mode"
                  phx-value-mode="once"
                  class={[
                    "flex-1 py-2 text-center transition-colors",
                    (@modal.url_mode == "once" && "bg-[color:var(--accent)] text-white font-medium") ||
                      "text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"
                  ]}
                  style="font-size: var(--t-meta);"
                >
                  {gettext("Engångshämtning")}
                </button>
                <button
                  phx-click="url_mode"
                  phx-value-mode="recurring"
                  class={[
                    "flex-1 py-2 text-center transition-colors",
                    (@modal.url_mode == "recurring" &&
                       "bg-[color:var(--accent)] text-white font-medium") ||
                      "text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"
                  ]}
                  style="font-size: var(--t-meta);"
                >
                  {gettext("Återkommande")}
                </button>
              </div>

              <%= if @modal.url_mode == "once" do %>
                <form phx-submit="scrape_once" class="space-y-3">
                  <.field
                    name="name"
                    label={gettext("Butiksnamn")}
                    placeholder="ICA Kvantum Sickla"
                    required
                  />
                  <.field
                    name="url"
                    label={gettext("URL till erbjudanden")}
                    placeholder="https://www.ica.se/erbjudanden/..."
                    required
                  />
                  <.button
                    type="submit"
                    variant={:primary}
                    size={:md}
                    class="w-full"
                    disabled={@scraping}
                  >
                    {gettext("Hämta erbjudanden")}
                  </.button>
                </form>
              <% else %>
                <form phx-submit="add_recurring" class="space-y-3">
                  <.field
                    name="name"
                    label={gettext("Butiksnamn")}
                    placeholder="ICA Kvantum Sickla"
                    required
                  />
                  <.field
                    name="url"
                    label={gettext("URL till erbjudanden")}
                    placeholder="https://www.ica.se/erbjudanden/..."
                    required
                  />
                  <.button type="submit" variant={:primary} size={:md} class="w-full">
                    {gettext("Spara källa")}
                  </.button>
                </form>
              <% end %>
            </div>
          <% end %>

          <%!-- PDF tab --%>
          <%= if @modal.tab == "pdf" do %>
            <div class="p-6 space-y-3">
              <form phx-change="validate_upload">
                <div
                  phx-drop-target={@uploads.deals_pdf.ref}
                  class="rounded-[var(--r-lg)] border-2 border-dashed border-[color:var(--border)] hover:border-[color:var(--accent)] transition-colors p-8 flex flex-col items-center gap-2 text-center"
                >
                  <.icon name="hero-document-arrow-up" class="size-10 text-[color:var(--subtle)]" />
                  <p class="text-[color:var(--muted)]" style="font-size: var(--t-body);">
                    {gettext("Släpp en PDF här eller")}
                  </p>
                  <label
                    for={@uploads.deals_pdf.ref}
                    class="cursor-pointer text-[color:var(--accent)] hover:underline"
                    style="font-size: var(--t-body);"
                  >
                    {gettext("välj fil")}
                    <.live_file_input upload={@uploads.deals_pdf} class="hidden" />
                  </label>
                  <p class="text-[color:var(--subtle)]" style="font-size: var(--t-meta);">
                    {gettext("Erbjudanden extraheras automatiskt · max 20 MB")}
                  </p>

                  <%= for entry <- @uploads.deals_pdf.entries do %>
                    <div class="w-full mt-3">
                      <div
                        class="flex items-center gap-2 text-[var(--text)]"
                        style="font-size: var(--t-meta);"
                      >
                        <.icon name="hero-document" class="size-4 shrink-0" />
                        <span class="truncate flex-1">{entry.client_name}</span>
                        <span class="tabular-nums">{entry.progress}%</span>
                      </div>
                      <div class="mt-1 h-1 rounded-full bg-[color:var(--hairline)] overflow-hidden">
                        <div
                          class="h-full bg-[color:var(--accent)] transition-all"
                          style={"width: #{entry.progress}%"}
                        />
                      </div>
                      <%= for err <- upload_errors(@uploads.deals_pdf, entry) do %>
                        <p class="text-[color:var(--danger)] mt-1" style="font-size: var(--t-meta);">
                          {upload_error_to_string(err)}
                        </p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </form>
              <p class="text-[color:var(--subtle)] text-center" style="font-size: var(--t-meta);">
                {gettext("Butikens namn extraheras från PDF:en av AI:n.")}
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp toggle_set(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  defp chain_from_url(url) do
    case URI.parse(url).host do
      host when is_binary(host) ->
        cond do
          String.contains?(host, "ica") -> "ica"
          String.contains?(host, "coop") -> "coop"
          true -> "ica"
        end

      _ ->
        "ica"
    end
  end

  defp upload_error_to_string(:too_large), do: gettext("Filen är för stor (max 20 MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Endast PDF-filer accepteras")
  defp upload_error_to_string(:too_many_files), do: gettext("Endast en fil åt gången")
  defp upload_error_to_string(_), do: gettext("Uppladdningsfel")

  defp nilify(""), do: nil
  defp nilify(v), do: v
end
