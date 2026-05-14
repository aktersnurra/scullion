defmodule ToreWeb.CostLive do
  use ToreWeb, :live_view

  alias Tore.Costs

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

  def handle_event("set_tab", %{"tab" => tab}, socket) do
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
        {:noreply, socket |> assign(summary: summary) |> put_flash(:info, gettext("Logged"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to log"))}
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
        {:noreply, socket |> assign(summary: summary) |> put_flash(:info, gettext("Receipt saved"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  defp load_tab(socket, :overview) do
    today = Date.utc_today()
    {:ok, summary} = Costs.monthly_summary(today.year, today.month)
    assign(socket, summary: summary)
  end

  defp load_tab(socket, _), do: socket

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

    assigns = assign(assigns, tabs: tabs, view_id: to_string(assigns.view), grocery_amt: grocery_amt, dining_amt: dining_amt, total_amt: total_amt, grocery_pct: grocery_pct, dining_pct: dining_pct)

    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/costs"}>
    <.page max_width={:md}>
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
              <%= if @current_user && @current_user.role in [:member, :admin] do %>
                <form phx-submit="save_manual_receipt" class="space-y-3 mb-4">
                  <div class="flex gap-3">
                    <div class="flex-1"><.field name="date" type="date" label={gettext("Date")} value={Date.to_iso8601(Date.utc_today())} required /></div>
                    <div class="flex-1"><.field name="store_name" label={gettext("Store")} placeholder="ICA Maxi" /></div>
                  </div>
                  <.field name="total_amount" type="number" label={gettext("Total (kr)")} placeholder="0.00" required />
                  <.button type="submit" variant={:primary} size={:lg} full>{gettext("Save receipt")}</.button>
                </form>
              <% end %>
              <.empty message={gettext("No receipts loaded")} />
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
              <% end %>
              <.empty message={gettext("Dining entries will appear here")} />
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
end
