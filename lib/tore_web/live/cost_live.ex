defmodule ToreWeb.CostLive do
  use ToreWeb, :live_view

  alias Tore.Costs
  alias Tore.Handlers.CostsHandler

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    {:ok, summary} = Costs.monthly_summary(today.year, today.month)

    socket =
      socket
      |> assign(
        view: :overview,
        summary: summary,
        receipts: [],
        dining_entries: [],
        scanning: false,
        receipt_preview: nil,
        scan_error: nil
      )
      |> allow_upload(:receipt_photo,
        accept: ~w(.jpg .jpeg .png .webp .heic),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    socket = load_tab(socket, tab)
    {:noreply, assign(socket, view: tab)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    socket = load_tab(socket, tab)
    {:noreply, assign(socket, view: tab)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("discard_receipt", _params, socket) do
    {:noreply, assign(socket, receipt_preview: nil, scan_error: nil)}
  end

  @impl true
  def handle_event("update_receipt_field", %{"field" => field, "value" => value}, socket) do
    preview = socket.assigns.receipt_preview

    updated =
      case field do
        "store_name" -> %{preview | store_name: nilify(value)}
        "total" -> %{preview | total: parse_decimal(value)}
        "date" -> %{preview | date: parse_date(value)}
        _ -> preview
      end

    {:noreply, assign(socket, receipt_preview: updated)}
  end

  @impl true
  def handle_event("update_receipt_item", %{"key" => key, "field" => field, "value" => value}, socket) do
    key = String.to_integer(key)
    preview = socket.assigns.receipt_preview

    items =
      Enum.map(preview.items, fn item ->
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

    {:noreply, assign(socket, receipt_preview: %{preview | items: items})}
  end

  @impl true
  def handle_event("remove_receipt_item", %{"key" => key}, socket) do
    key = String.to_integer(key)
    preview = socket.assigns.receipt_preview
    items = Enum.reject(preview.items, &(&1.key == key))
    {:noreply, assign(socket, receipt_preview: %{preview | items: items})}
  end

  @impl true
  def handle_event("confirm_receipt", _params, socket) do
    preview = socket.assigns.receipt_preview
    user_id = socket.assigns.current_user.id

    case CostsHandler.confirm_receipt(preview, user_id) do
      {:ok, _} ->
        today = Date.utc_today()
        {:ok, summary} = Costs.monthly_summary(today.year, today.month)

        {:noreply,
         socket
         |> assign(receipt_preview: nil, summary: summary)
         |> put_flash(:info, gettext("Receipt saved and items added to pantry"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save receipt"))}
    end
  end

  @impl true
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
        {:noreply, socket |> assign(summary: summary) |> put_flash(:info, gettext("Logged"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to log"))}
    end
  end

  @impl true
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
        {:noreply, socket |> assign(summary: summary) |> put_flash(:info, gettext("Receipt saved"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_progress(:receipt_photo, entry, socket) do
    if entry.done? do
      [{binary, _}] =
        consume_uploaded_entries(socket, :receipt_photo, fn %{path: path}, e ->
          {:ok, {File.read!(path), e}}
        end)

      pid = self()
      Task.start(fn -> send(pid, {:receipt_scan_result, CostsHandler.parse_receipt_image(binary)}) end)

      {:noreply, assign(socket, scanning: true, scan_error: nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:receipt_scan_result, {:ok, result, _usage}}, socket) do
    items =
      Enum.with_index(result.items, fn item, i -> Map.put(item, :key, i) end)

    preview = %{
      total: result.total,
      store_name: result.store_name,
      date: Date.utc_today(),
      items: items
    }

    {:noreply, assign(socket, scanning: false, receipt_preview: preview)}
  end

  @impl true
  def handle_info({:receipt_scan_result, {:error, reason}}, socket) do
    require Logger
    Logger.error("receipt_scan_result error: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       scanning: false,
       scan_error: gettext("Could not read receipt. Try a clearer photo.")
     )}
  end

  defp load_tab(socket, :overview) do
    today = Date.utc_today()
    {:ok, summary} = Costs.monthly_summary(today.year, today.month)
    assign(socket, summary: summary)
  end

  defp load_tab(socket, :receipts) do
    assign(socket, receipts: Costs.list_receipts())
  end

  defp load_tab(socket, _), do: socket

  @impl true
  def render(assigns) do
    tabs = [
      %{id: "overview", label: gettext("Overview")},
      %{id: "receipts", label: gettext("Receipts")},
      %{id: "dining", label: gettext("Dining")}
    ]

    grocery_amt = decimal_to_int(assigns.summary.grocery_total)
    dining_amt = decimal_to_int(assigns.summary.dining_total)
    total_amt = decimal_to_int(assigns.summary.total)
    grocery_pct = if total_amt > 0, do: round(grocery_amt * 100 / total_amt), else: 0
    dining_pct = if total_amt > 0, do: 100 - grocery_pct, else: 0

    assigns =
      assign(assigns,
        tabs: tabs,
        view_id: to_string(assigns.view),
        grocery_amt: grocery_amt,
        dining_amt: dining_amt,
        total_amt: total_amt,
        grocery_pct: grocery_pct,
        dining_pct: dining_pct
      )

    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/costs"}>
    <.page max_width={:md}>

      <%!-- ── Receipt scan preview ───────────────────────────────────────── --%>
      <%= if @receipt_preview do %>
        <.card padded={false} class="mb-4">
          <header class="px-6 pt-6 pb-3 flex items-center justify-between">
            <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">{gettext("Review receipt")}</h2>
            <span class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{length(@receipt_preview.items)} {gettext("items")}</span>
          </header>

          <div class="px-6 pb-4 border-t border-[color:var(--hairline)] pt-4 space-y-3">
            <div class="grid grid-cols-2 gap-3">
              <input
                type="text"
                value={@receipt_preview.store_name}
                placeholder={gettext("Store")}
                phx-blur="update_receipt_field"
                phx-value-field="store_name"
                class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-meta);"
              />
              <input
                type="date"
                value={Date.to_iso8601(@receipt_preview.date)}
                phx-blur="update_receipt_field"
                phx-value-field="date"
                class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-meta);"
              />
            </div>
            <div class="flex items-center gap-2">
              <input
                type="number"
                value={@receipt_preview.total && Decimal.to_string(@receipt_preview.total)}
                placeholder={gettext("Total (kr)")}
                phx-blur="update_receipt_field"
                phx-value-field="total"
                class="flex-1 rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-meta);"
              />
              <span class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">kr</span>
            </div>
          </div>

          <p class="px-6 pb-2 text-[color:var(--muted)] font-medium" style="font-size: var(--t-meta);">{gettext("Add to pantry")}</p>

          <ul class="border-t border-[color:var(--hairline)] divide-y divide-[color:var(--hairline)]">
            <li :for={item <- @receipt_preview.items} class="px-6 py-3 flex items-start gap-3">
              <div class="flex-1 grid grid-cols-2 gap-2">
                <input
                  type="text"
                  value={item.name}
                  placeholder={gettext("Name")}
                  phx-blur="update_receipt_item"
                  phx-value-key={item.key}
                  phx-value-field="name"
                  class="col-span-2 w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                  style="font-size: var(--t-meta);"
                />
                <input
                  type="text"
                  value={item.quantity && Decimal.to_string(item.quantity)}
                  placeholder={gettext("Qty")}
                  phx-blur="update_receipt_item"
                  phx-value-key={item.key}
                  phx-value-field="quantity"
                  class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                  style="font-size: var(--t-meta);"
                />
                <input
                  type="text"
                  value={item.unit}
                  placeholder={gettext("Unit")}
                  phx-blur="update_receipt_item"
                  phx-value-key={item.key}
                  phx-value-field="unit"
                  class="w-full rounded-[var(--r-md)] border border-[color:var(--border)] bg-[var(--surface)] px-3 py-1.5 text-[var(--text)] focus:outline-none focus:border-[color:var(--accent)]"
                  style="font-size: var(--t-meta);"
                />
              </div>
              <button
                phx-click="remove_receipt_item"
                phx-value-key={item.key}
                class="mt-1 size-8 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]"
                aria-label={gettext("Remove")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </li>
          </ul>

          <div class="px-6 py-4 flex gap-3 border-t border-[color:var(--hairline)]">
            <.button phx-click="confirm_receipt" variant={:primary} size={:lg} full>{gettext("Save receipt & add to pantry")}</.button>
            <.button phx-click="discard_receipt" variant={:ghost} size={:lg}>{gettext("Discard")}</.button>
          </div>
        </.card>
      <% end %>

      <%!-- ── Main costs card ──────────────────────────────────────────────── --%>
      <.card padded={false}>
        <header class="flex items-center justify-between px-6 pt-6 pb-3">
          <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">{gettext("Costs")}</h1>
          <button
            type="button"
            class="h-9 px-3 inline-flex items-center gap-1.5 rounded-[var(--r-lg)] border border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
            style="font-size: var(--t-meta);"
          >
            {gettext("This month")} <.icon name="hero-chevron-down" class="size-3.5" />
          </button>
        </header>

        <div class="px-6 pb-5 border-t border-[color:var(--hairline)] pt-5">
          <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Total spend")}</p>
          <p class="mt-1 font-semibold text-[var(--text)]" style="font-size: var(--t-display);">{format_money(@total_amt)} kr</p>

          <div class="mt-5 divide-y divide-[color:var(--hairline)]">
            <div class="flex items-center gap-3 py-3">
              <span class="size-2.5 rounded-full bg-[color:var(--accent)] shrink-0"></span>
              <span class="flex-1 text-[var(--text)]" style="font-size: var(--t-body);">{gettext("Groceries")}</span>
              <span class="text-[var(--text)] font-medium tabular-nums" style="font-size: var(--t-body);">{format_money(@grocery_amt)} kr</span>
              <span class="w-10 text-right text-[color:var(--muted)] tabular-nums" style="font-size: var(--t-meta);">{@grocery_pct}%</span>
            </div>
            <div class="flex items-center gap-3 py-3">
              <span class="size-2.5 rounded-full bg-[color:var(--warn)] shrink-0"></span>
              <span class="flex-1 text-[var(--text)]" style="font-size: var(--t-body);">{gettext("Dining out")}</span>
              <span class="text-[var(--text)] font-medium tabular-nums" style="font-size: var(--t-body);">{format_money(@dining_amt)} kr</span>
              <span class="w-10 text-right text-[color:var(--muted)] tabular-nums" style="font-size: var(--t-meta);">{@dining_pct}%</span>
            </div>
          </div>
        </div>

        <div class="px-6 pt-2 border-t border-[color:var(--hairline)]">
          <.tabs items={@tabs} active={@view_id} />
        </div>

        <div class="px-6 py-5">
          <%= cond do %>
            <% @view == :overview -> %>
              <div class="grid grid-cols-3 gap-3">
                <div class="text-center">
                  <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Receipts")}</p>
                  <p class="mt-1 font-semibold" style="font-size: var(--t-h2);">{@summary.receipt_count}</p>
                </div>
                <div class="text-center">
                  <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Dining")}</p>
                  <p class="mt-1 font-semibold" style="font-size: var(--t-h2);">{@summary.dining_count}</p>
                </div>
                <div class="text-center">
                  <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Total")}</p>
                  <p class="mt-1 font-semibold" style="font-size: var(--t-h2);">{format_money(@total_amt)} kr</p>
                </div>
              </div>

            <% @view == :receipts -> %>
              <%= if @current_user && @current_user.role in [:member, :admin] && !@receipt_preview do %>
                <div class="mb-5">
                  <%= if @scanning do %>
                    <div class="flex items-center justify-center gap-2 py-6 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                      <.icon name="hero-arrow-path" class="size-4 animate-spin" /> {gettext("Scanning receipt…")}
                    </div>
                  <% else %>
                    <form phx-change="validate_upload" class="mb-4">
                      <.live_file_input upload={@uploads.receipt_photo} class="hidden" />
                      <label
                        for={@uploads.receipt_photo.ref}
                        class="cursor-pointer w-full flex items-center justify-center gap-2 py-3 rounded-[var(--r-lg)] border border-dashed border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)] hover:text-[var(--text)]"
                        style="font-size: var(--t-meta);"
                      >
                        <.icon name="hero-camera" class="size-4" /> {gettext("Scan receipt photo")}
                      </label>
                    </form>

                    <p :if={@scan_error} class="mb-3 text-[color:var(--danger)] bg-red-50 rounded-[var(--r-lg)] py-2 px-3" style="font-size: var(--t-meta);">{@scan_error}</p>

                    <form phx-submit="save_manual_receipt" class="space-y-3">
                      <p class="text-[color:var(--muted)] font-medium" style="font-size: var(--t-meta);">{gettext("Or enter manually")}</p>
                      <div class="flex gap-3">
                        <div class="flex-1"><.field name="date" type="date" label={gettext("Date")} value={Date.to_iso8601(Date.utc_today())} required /></div>
                        <div class="flex-1"><.field name="store_name" label={gettext("Store")} placeholder="ICA Maxi" /></div>
                      </div>
                      <.field name="total_amount" type="number" label={gettext("Total (kr)")} placeholder="0.00" required />
                      <.button type="submit" variant={:secondary} size={:md} full>{gettext("Save receipt")}</.button>
                    </form>
                  <% end %>
                </div>
              <% end %>

              <%= if @receipts == [] do %>
                <.empty message={gettext("No receipts yet")} />
              <% else %>
                <ul class="divide-y divide-[color:var(--hairline)] -mx-6 px-6">
                  <li :for={receipt <- @receipts} class="py-3 flex items-center gap-3">
                    <div class="flex-1 min-w-0">
                      <p class="font-medium text-[var(--text)]" style="font-size: var(--t-body);">{receipt.store_name || gettext("Unknown store")}</p>
                      <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{Date.to_iso8601(receipt.date)}</p>
                    </div>
                    <span class="font-medium tabular-nums text-[var(--text)]" style="font-size: var(--t-body);">
                      {receipt.total_amount && "#{format_money(decimal_to_int(receipt.total_amount))} kr"}
                    </span>
                  </li>
                </ul>
              <% end %>

            <% @view == :dining -> %>
              <%= if @current_user && @current_user.role in [:member, :admin] do %>
                <form phx-submit="log_dining_out" class="space-y-3 mb-4">
                  <div class="flex gap-3">
                    <div class="flex-1"><.field name="date" type="date" label={gettext("Date")} value={Date.to_iso8601(Date.utc_today())} required /></div>
                    <div class="flex-1"><.field name="num_people" type="number" label={gettext("People")} value="1" /></div>
                  </div>
                  <.field name="description" label={gettext("Restaurant / occasion")} placeholder={gettext("Sushi night")} />
                  <.field name="total_amount" type="number" label={gettext("Total (kr)")} placeholder="0.00" required />
                  <.button type="submit" variant={:primary} size={:lg} full>{gettext("Log dining")}</.button>
                </form>
                <.empty message={gettext("Dining entries will appear here")} />
              <% end %>
          <% end %>
        </div>
      </.card>
    </.page>
    </Layouts.app>
    """
  end

  defp decimal_to_int(%Decimal{} = d), do: Decimal.to_integer(Decimal.round(d, 0))
  defp decimal_to_int(n) when is_integer(n), do: n
  defp decimal_to_int(_), do: 0

  defp format_money(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(" ", &Enum.join/1)
    |> String.reverse()
  end

  defp parse_decimal(""), do: nil
  defp parse_decimal(nil), do: nil
  defp parse_decimal(s) do
    case Decimal.parse(s) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_date(""), do: Date.utc_today()
  defp parse_date(nil), do: Date.utc_today()
  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  defp nilify(""), do: nil
  defp nilify(v), do: v
end
