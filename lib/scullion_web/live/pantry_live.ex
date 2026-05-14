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
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Failed to add item"))}
    end
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    Pantry.remove_item(String.to_integer(id))
    {:noreply, assign(socket, items: Pantry.list_inventory())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/pantry"}>
    <.page max_width={:md}>
      <.card padded={false}>
        <header class="px-6 pt-6 pb-3">
          <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">{gettext("Pantry")}</h1>
        </header>

        <%= if @items == [] do %>
          <div class="px-6 py-8 border-t border-[color:var(--hairline)]"><.empty message={gettext("Nothing in pantry yet")} /></div>
        <% else %>
          <ul class="px-6 pt-2 border-t border-[color:var(--hairline)] divide-y divide-[color:var(--hairline)]">
            <li :for={item <- @items} class={["flex items-center gap-3 py-3", expiring_soon?(item.expires_at) && "text-[color:var(--danger)]"]}>
              <div class="flex-1 min-w-0">
                <p class="font-medium" style="font-size: var(--t-body);">{item.name}</p>
                <p :if={item.category || item.expires_at} class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                  <span :if={item.category}>{item.category}</span>
                  <span :if={item.category && item.expires_at}> · </span>
                  <span :if={item.expires_at}>{gettext("expires %{date}", date: format_date(item.expires_at))}</span>
                </p>
              </div>
              <span class="shrink-0 text-[color:var(--muted)] tabular-nums" style="font-size: var(--t-meta);">
                {format_qty(item.quantity, item.unit)}
              </span>
              <%= if @current_user && @current_user.role in [:member, :admin] do %>
                <button phx-click="remove_item" phx-value-id={item.id}
                        class="size-9 inline-flex items-center justify-center text-[color:var(--subtle)] hover:text-[color:var(--danger)]" aria-label={gettext("Remove")}>
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              <% end %>
            </li>
          </ul>
        <% end %>

        <%= if @current_user && @current_user.role in [:member, :admin] do %>
          <form phx-submit="add_item" class="px-6 py-5 mt-2 border-t border-[color:var(--hairline)] space-y-4">
            <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">{gettext("Add to pantry")}</h2>
            <.field name="name" label={gettext("Item")} placeholder={gettext("e.g. Pasta")} required />
            <div class="grid grid-cols-2 gap-3">
              <.field name="quantity" label={gettext("Quantity")} placeholder="500" />
              <.field name="unit" label={gettext("Unit")} placeholder="g" />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <.field name="category" label={gettext("Category")} placeholder={gettext("dairy")} />
              <.field name="expires_at" label={gettext("Expires")} type="date" />
            </div>
            <.button type="submit" variant={:primary} size={:lg} full>{gettext("Add")}</.button>
          </form>
        <% end %>
      </.card>
    </.page>
    </Layouts.app>
    """
  end

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
