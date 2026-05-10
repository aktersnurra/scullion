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
       week_number: week_number(week_start),
       list_id: list_id,
       grocery_state: grocery_state,
       user_id: user_id,
       export_text: nil
     )}
  end

  def handle_event("toggle_item", %{"item_id" => id}, socket) do
    item = Map.get(socket.assigns.grocery_state.items, id)

    if item && item.checked do
      GroceriesHandler.uncheck_item(socket.assigns.list_id, id, socket.assigns.user_id)
    else
      GroceriesHandler.check_item(socket.assigns.list_id, id, socket.assigns.user_id)
    end

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

  def handle_event("clear_export", _params, socket) do
    {:noreply, assign(socket, export_text: nil)}
  end

  def handle_event("add_item", %{"name" => name} = params, socket) do
    name = String.trim(name)

    if name != "" do
      qty = Map.get(params, "quantity", "")
      unit = Map.get(params, "unit", "")
      quantity = if qty == "", do: nil, else: parse_qty(qty)
      unit = if unit == "", do: nil, else: unit
      GroceriesHandler.add_item(socket.assigns.list_id, name, quantity, unit, socket.assigns.user_id)
    end

    {:noreply, socket}
  end

  def handle_info({:events, _events}, socket) do
    {:ok, grocery_state} = GroceriesHandler.load_list(socket.assigns.list_id)
    {:noreply, assign(socket, grocery_state: grocery_state)}
  end

  def render(assigns) do
    items = sorted_items(assigns.grocery_state.items)
    {unchecked, checked} = Enum.split_with(items, &(!&1.checked))
    assigns = assign(assigns, unchecked: unchecked, checked: checked, total: length(items), unchecked_count: length(unchecked))

    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/groceries"}>
    <.page max_width={:md}>
      <.card padded={false}>
        <header class="flex items-start justify-between gap-4 px-6 pt-6 pb-4">
          <div>
            <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">Groceries</h1>
            <p class="mt-0.5 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
              {@unchecked_count} unchecked · Week {@week_number}
            </p>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <button
              type="button"
              class="h-9 px-3 inline-flex items-center gap-1.5 rounded-[var(--r-lg)] border border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
              style="font-size: var(--t-meta);"
            >
              <.icon name="hero-funnel" class="size-4" /> Group by category
              <.icon name="hero-chevron-down" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click="export_list"
              aria-label="More"
              class="size-9 inline-flex items-center justify-center rounded-[var(--r-lg)] border border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
            >
              <.icon name="hero-ellipsis-horizontal" class="size-4" />
            </button>
          </div>
        </header>

        <div :if={@export_text} class="mx-6 mb-4 border border-[color:var(--border)] rounded-[var(--r-lg)] p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-[color:var(--muted)]" style="font-size: var(--t-meta); font-weight: 500;">
              Export
            </span>
            <.icon_button icon="hero-x-mark" label="Close" phx-click="clear_export" />
          </div>
          <textarea
            readonly
            class="w-full bg-transparent text-[var(--text)] font-mono resize-none focus:outline-none"
            style="font-size: var(--t-meta);"
            rows="6"
          ><%= @export_text %></textarea>
        </div>

        <div class="px-6 pb-3">
          <%= if @total == 0 do %>
            <.empty message="No items yet" />
          <% else %>
            <ul class="divide-y divide-[color:var(--hairline)]">
              <.grocery_row :for={item <- @unchecked} item={item} />
            </ul>

            <%= if @checked != [] do %>
              <h2 class="uppercase tracking-wider text-[color:var(--subtle)] mt-6 mb-1" style="font-size: var(--t-micro); font-weight: 600;">
                Done · {length(@checked)}
              </h2>
              <ul class="divide-y divide-[color:var(--hairline)]">
                <.grocery_row :for={item <- @checked} item={item} />
              </ul>
            <% end %>
          <% end %>

          <form phx-submit="add_item" class="mt-2 pt-3 border-t border-[color:var(--hairline)] flex items-center gap-3">
            <.icon name="hero-plus" class="size-5 text-[color:var(--accent)] shrink-0" />
            <input
              type="text"
              name="name"
              placeholder="Add item…"
              required
              class="flex-1 h-10 bg-transparent border-0 text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none"
              style="font-size: var(--t-body);"
            />
            <input
              type="text"
              name="quantity"
              placeholder="Qty"
              inputmode="decimal"
              class="w-16 h-10 bg-transparent border-0 text-[color:var(--muted)] placeholder:text-[color:var(--subtle)] tabular-nums text-right focus:outline-none"
              style="font-size: var(--t-meta);"
            />
            <input
              type="text"
              name="unit"
              placeholder="Unit"
              class="w-12 h-10 bg-transparent border-0 text-[color:var(--muted)] placeholder:text-[color:var(--subtle)] focus:outline-none"
              style="font-size: var(--t-meta);"
            />
          </form>
        </div>
      </.card>
    </.page>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true

  defp grocery_row(assigns) do
    ~H"""
    <li class={[
      "flex items-center gap-4 py-3 transition-opacity",
      @item.checked && "opacity-50"
    ]}>
      <.checkbox checked={@item.checked} phx-click="toggle_item" phx-value-item_id={@item.id} />
      <button
        type="button"
        phx-click="toggle_item"
        phx-value-item_id={@item.id}
        class="flex-1 min-w-0 text-left"
      >
        <span
          class={[
            "text-[var(--text)] truncate",
            @item.checked && "line-through"
          ]}
          style="font-size: var(--t-body);"
        >
          {@item.name}
        </span>
      </button>
      <span
        :if={qty_label(@item) != ""}
        class="shrink-0 text-[color:var(--muted)] tabular-nums"
        style="font-size: var(--t-meta);"
      >
        {qty_label(@item)}
      </span>
      <button
        type="button"
        phx-click="remove_item"
        phx-value-item_id={@item.id}
        aria-label="Remove"
        class="size-9 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </li>
    """
  end

  defp sorted_items(items) do
    items
    |> Map.values()
    |> Enum.sort_by(fn i -> {i.checked, String.downcase(i.name)} end)
  end

  defp qty_label(%{quantity: nil, unit: nil}), do: ""
  defp qty_label(%{quantity: nil, unit: unit}), do: unit
  defp qty_label(%{quantity: qty, unit: nil}), do: format_decimal(qty)
  defp qty_label(%{quantity: qty, unit: unit}), do: "#{format_decimal(qty)} #{unit}"

  defp format_decimal(%Decimal{} = d) do
    if Decimal.integer?(d), do: Decimal.to_string(Decimal.normalize(d)), else: Decimal.to_string(d)
  end

  defp format_decimal(other), do: to_string(other)

  defp parse_qty(s) do
    case Decimal.parse(s) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp week_number(date) do
    {_y, w} = :calendar.iso_week_number({date.year, date.month, date.day})
    w
  end

  defp grocery_id(week_start), do: "grocery_list:#{Date.to_iso8601(week_start)}"
end
