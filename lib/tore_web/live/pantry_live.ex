defmodule ToreWeb.PantryLive do
  use ToreWeb, :live_view

  alias Tore.Pantry
  alias Tore.Handlers.PantryHandler
  alias Tore.Pantry.PantryItem

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        groups: Pantry.list_inventory_grouped(),
        scanning: false,
        preview: nil,
        scan_error: nil,
        new_category: nil
      )
      |> allow_upload(:pantry_photo,
        accept: ~w(.jpg .jpeg .png .webp .heic),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("add_item", params, socket) do
    attrs = %{
      name: params["name"],
      quantity: parse_decimal(params["quantity"]),
      unit: nilify(params["unit"]),
      category: nilify(params["category"]),
      expires_at: parse_date(params["expires_at"])
    }

    case Pantry.add_item(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(groups: Pantry.list_inventory_grouped(), new_category: nil)
         |> push_event("reset_form", %{id: "add-item-form"})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add item"))}
    end
  end

  @impl true
  def handle_event("set_category", %{"cat" => value}, socket) do
    {:noreply, assign(socket, new_category: nilify(value))}
  end

  @impl true
  def handle_event("set_preview_category", %{"key" => key, "cat" => value}, socket) do
    key = String.to_integer(key)

    preview =
      Enum.map(socket.assigns.preview, fn item ->
        if item.key == key, do: %{item | category: nilify(value)}, else: item
      end)

    {:noreply, assign(socket, preview: preview)}
  end

  @impl true
  def handle_event("remove_item", %{"id" => id}, socket) do
    Pantry.remove_item(String.to_integer(id))
    {:noreply, assign(socket, groups: Pantry.list_inventory_grouped())}
  end

  @impl true
  def handle_event("discard_scan", _params, socket) do
    {:noreply, assign(socket, preview: nil, scan_error: nil)}
  end

  @impl true
  def handle_event("confirm_scan", _params, socket) do
    items = socket.assigns.preview || []

    case PantryHandler.confirm_items(items) do
      {:ok, _inserted} ->
        {:noreply,
         socket
         |> assign(preview: nil, groups: Pantry.list_inventory_grouped())
         |> put_flash(:info, gettext("Items added to pantry"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save some items"))}
    end
  end

  @impl true
  def handle_event(
        "update_preview_item",
        %{"key" => key, "field" => field, "value" => value},
        socket
      ) do
    key = String.to_integer(key)

    preview =
      Enum.map(socket.assigns.preview, fn item ->
        if item.key == key do
          case field do
            "name" -> %{item | name: value}
            "quantity" -> %{item | quantity: parse_decimal(value)}
            "unit" -> %{item | unit: nilify(value)}
            "category" -> %{item | category: nilify(value)}
            _ -> item
          end
        else
          item
        end
      end)

    {:noreply, assign(socket, preview: preview)}
  end

  @impl true
  def handle_event("remove_preview_item", %{"key" => key}, socket) do
    key = String.to_integer(key)
    preview = Enum.reject(socket.assigns.preview, &(&1.key == key))
    {:noreply, assign(socket, preview: preview)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_progress(:pantry_photo, entry, socket) do
    if entry.done? do
      [{binary, _}] =
        consume_uploaded_entries(socket, :pantry_photo, fn %{path: path}, e ->
          {:ok, {File.read!(path), e}}
        end)

      pid = self()
      Task.start(fn -> send(pid, {:pantry_scan_result, PantryHandler.parse_image(binary)}) end)

      {:noreply, assign(socket, scanning: true, scan_error: nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:pantry_scan_result, {:ok, items, _usage}}, socket) do
    preview =
      Enum.with_index(items, fn item, i ->
        Map.put(item, :key, i)
      end)

    {:noreply, assign(socket, scanning: false, preview: preview)}
  end

  @impl true
  def handle_info({:pantry_scan_result, {:error, reason}}, socket) do
    require Logger
    Logger.error("pantry_scan_result error: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       scanning: false,
       scan_error: gettext("Could not read image. Try a clearer photo.")
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/pantry"}>
      <.page max_width={:md}>
        <%!-- ── Scan preview ─────────────────────────────────────────────── --%>
        <%= if @preview do %>
          <.card padded={false} class="mb-4">
            <header class="px-6 pt-6 pb-3 flex items-center justify-between">
              <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">
                {gettext("Review scanned items")}
              </h2>
              <span class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                {length(@preview)} {gettext("items")}
              </span>
            </header>

            <ul class="border-t border-[color:var(--hairline)] divide-y divide-[color:var(--hairline)]">
              <li :for={item <- @preview} class="px-6 py-3 flex items-start gap-3">
                <div class="flex-1 space-y-2">
                  <input
                    type="text"
                    value={item.name}
                    placeholder={gettext("Name")}
                    phx-blur="update_preview_item"
                    phx-value-key={item.key}
                    phx-value-field="name"
                    class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                    style="font-size: var(--t-meta);"
                  />
                  <div class="grid grid-cols-2 gap-2">
                    <input
                      type="text"
                      value={item.quantity && Decimal.to_string(item.quantity)}
                      placeholder={gettext("Qty")}
                      phx-blur="update_preview_item"
                      phx-value-key={item.key}
                      phx-value-field="quantity"
                      class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                      style="font-size: var(--t-meta);"
                    />
                    <input
                      type="text"
                      value={item.unit}
                      placeholder={gettext("Unit")}
                      phx-blur="update_preview_item"
                      phx-value-key={item.key}
                      phx-value-field="unit"
                      class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                      style="font-size: var(--t-meta);"
                    />
                  </div>
                  <div class="flex flex-wrap gap-1.5">
                    <button
                      :for={cat <- PantryItem.categories()}
                      type="button"
                      phx-click="set_preview_category"
                      phx-value-key={item.key}
                      phx-value-cat={Atom.to_string(cat)}
                      class={[
                        "px-2.5 py-1 rounded-full border text-xs font-medium transition-colors",
                        item.category == Atom.to_string(cat)
                          && "border-[color:var(--accent)] bg-[color:var(--accent)] text-white"
                          || "border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
                      ]}
                    >
                      {category_label(cat)}
                    </button>
                  </div>
                </div>
                <button
                  phx-click="remove_preview_item"
                  phx-value-key={item.key}
                  class="mt-1 size-8 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]"
                  aria-label={gettext("Remove")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </li>
            </ul>

            <div class="px-6 py-4 flex gap-3 border-t border-[color:var(--hairline)]">
              <.button phx-click="confirm_scan" variant={:primary} size={:lg} full>
                {gettext("Add to pantry")}
              </.button>
              <.button phx-click="discard_scan" variant={:ghost} size={:lg}>
                {gettext("Discard")}
              </.button>
            </div>
          </.card>
        <% end %>

        <%!-- ── Main pantry card ──────────────────────────────────────────── --%>
        <.card padded={false}>
          <header class="px-6 pt-6 pb-3 flex items-center justify-between">
            <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">
              {gettext("Pantry")}
            </h1>
            <%= if @current_user && @current_user.role in [:member, :admin] && !@preview do %>
              <%= if @scanning do %>
                <span
                  class="text-[color:var(--muted)] inline-flex items-center gap-1.5"
                  style="font-size: var(--t-meta);"
                >
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" /> {gettext("Scanning…")}
                </span>
              <% else %>
                <form phx-change="validate_upload">
                  <.live_file_input upload={@uploads.pantry_photo} class="hidden" />
                  <label
                    for={@uploads.pantry_photo.ref}
                    class="cursor-pointer h-9 px-3 inline-flex items-center gap-1.5 rounded-[var(--r-lg)] border border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
                    style="font-size: var(--t-meta);"
                  >
                    <.icon name="hero-camera" class="size-4" /> {gettext("Scan photo")}
                  </label>
                </form>
              <% end %>
            <% end %>
          </header>

          <p
            :if={@scan_error}
            class="mx-6 mb-3 text-[color:var(--danger)] bg-red-50 rounded-[var(--r-lg)] py-2 px-3"
            style="font-size: var(--t-meta);"
          >
            {@scan_error}
          </p>

          <%= if @groups == [] do %>
            <div class="px-6 py-8 border-t border-[color:var(--hairline)]">
              <.empty message={gettext("Nothing in pantry yet")} />
            </div>
          <% else %>
            <div class="border-t border-[color:var(--hairline)]">
              <div :for={{category, items} <- @groups}>
                <p
                  class="px-6 pt-4 pb-1 text-[color:var(--muted)] uppercase tracking-wide font-semibold"
                  style="font-size: var(--t-meta);"
                >
                  {category_label(category)}
                </p>
                <ul class="divide-y divide-[color:var(--hairline)]">
                  <li
                    :for={item <- items}
                    class={[
                      "px-6 flex items-center gap-3 py-3",
                      expiring_soon?(item.expires_at) && "text-[color:var(--danger)]"
                    ]}
                  >
                    <div class="flex-1 min-w-0">
                      <p class="font-medium" style="font-size: var(--t-body);">
                        {String.capitalize(item.name)}
                      </p>
                      <p
                        :if={item.expires_at}
                        class="text-[color:var(--muted)]"
                        style="font-size: var(--t-meta);"
                      >
                        {gettext("expires %{date}", date: format_date(item.expires_at))}
                      </p>
                    </div>
                    <span
                      class="shrink-0 text-[color:var(--muted)] tabular-nums"
                      style="font-size: var(--t-meta);"
                    >
                      {format_qty(item.quantity, item.unit)}
                    </span>
                    <%= if @current_user && @current_user.role in [:member, :admin] do %>
                      <button
                        phx-click="remove_item"
                        phx-value-id={item.id}
                        class="size-9 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]"
                        aria-label={gettext("Remove")}
                      >
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    <% end %>
                  </li>
                </ul>
              </div>
            </div>
          <% end %>

          <%= if @current_user && @current_user.role in [:member, :admin] do %>
            <form
              id="add-item-form"
              phx-submit="add_item"
              class="px-6 py-5 mt-2 border-t border-[color:var(--hairline)] space-y-4"
            >
              <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">
                {gettext("Add to pantry")}
              </h2>
              <.field
                name="name"
                label={gettext("Item")}
                placeholder={gettext("e.g. Pasta")}
                required
              />
              <div class="grid grid-cols-2 gap-3">
                <.field name="quantity" label={gettext("Quantity")} placeholder="500" />
                <.field name="unit" label={gettext("Unit")} placeholder="g" />
              </div>
              <div>
                <p class="mb-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                  {gettext("Category")}
                </p>
                <input type="hidden" name="category" value={@new_category || ""} />
                <div class="flex flex-wrap gap-1.5">
                  <button
                    :for={cat <- PantryItem.categories()}
                    type="button"
                    phx-click="set_category"
                    phx-value-cat={Atom.to_string(cat)}
                    class={[
                      "px-2.5 py-1 rounded-full border text-xs font-medium transition-colors",
                      @new_category == Atom.to_string(cat)
                        && "border-[color:var(--accent)] bg-[color:var(--accent)] text-white"
                        || "border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
                    ]}
                  >
                    {category_label(cat)}
                  </button>
                </div>
              </div>
              <.field name="expires_at" label={gettext("Expires")} type="date" />
              <.button type="submit" variant={:primary} size={:lg} full>{gettext("Add")}</.button>
            </form>
          <% end %>
        </.card>
      </.page>
    </Layouts.app>
    """
  end

  defp category_label(nil), do: gettext("Other")
  defp category_label(:dairy), do: gettext("Dairy")
  defp category_label(:meat), do: gettext("Meat & fish")
  defp category_label(:produce), do: gettext("Produce")
  defp category_label(:frozen), do: gettext("Frozen")
  defp category_label(:dry_goods), do: gettext("Dry goods")
  defp category_label(:canned), do: gettext("Canned & jarred")
  defp category_label(:herbs_spices), do: gettext("Herbs & spices")
  defp category_label(:condiments), do: gettext("Condiments")
  defp category_label(:other), do: gettext("Other")

  defp expiring_soon?(nil), do: false
  defp expiring_soon?(d), do: Date.diff(d, Date.utc_today()) <= 3

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
end
