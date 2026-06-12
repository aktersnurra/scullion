defmodule ToreWeb.ReviewLive do
  use ToreWeb, :live_view

  @impl true
  def mount(%{"class" => class, "id" => id}, _session, socket) do
    review =
      case :ets.whereis(:chat_reviews) do
        :undefined ->
          nil

        _ ->
          case :ets.lookup(:chat_reviews, id) do
            [{^id, review}] -> review
            [] -> nil
          end
      end

    if review == nil do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      class_atom = String.to_existing_atom(class)
      {:ok, assign(socket, class: class_atom, review_id: id, result: review.result, saved: false)}
    end
  end

  @impl true
  def handle_event("confirm", _params, %{assigns: %{class: :recipe}} = socket) do
    result = socket.assigns.result

    attrs = %{
      title: result[:title] || result["title"] || "Untitled",
      instructions: result[:instructions] || result["instructions"],
      base_servings:
        result[:base_servings] || result["base_servings"] || result[:servings] ||
          result["servings"] || 4,
      ingredients: result[:ingredients] || result["ingredients"] || []
    }

    case Tore.Recipes.create(attrs) do
      {:ok, _recipe} -> {:noreply, assign(socket, :saved, true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save recipe.")}
    end
  end

  def handle_event("confirm", _params, %{assigns: %{class: :receipt}} = socket) do
    result = socket.assigns.result

    attrs = %{
      total: result[:total] || result["total"],
      store_name: result[:store_name] || result["store_name"],
      items: result[:items] || result["items"] || [],
      date: Date.utc_today()
    }

    case Tore.Handlers.CostsHandler.confirm_receipt(attrs, socket.assigns.current_user.id) do
      {:ok, _} -> {:noreply, assign(socket, :saved, true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save receipt.")}
    end
  end

  def handle_event("confirm", _params, %{assigns: %{class: :pantry_items}} = socket) do
    case Tore.Pantry.confirm_items(socket.assigns.result) do
      {:ok, _} -> {:noreply, assign(socket, :saved, true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to add pantry items.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/review">
      <div class="max-w-2xl mx-auto px-4 py-6">
        <.link
          navigate={~p"/capture"}
          class="text-[color:var(--muted)] text-sm mb-4 inline-flex items-center gap-1"
        >
          <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to chat")}
        </.link>

        {render_review(assigns)}
      </div>
    </Layouts.app>
    """
  end

  defp render_review(%{class: :recipe} = assigns) do
    ~H"""
    <h2 class="text-xl font-semibold text-[color:var(--text)] mb-4">
      {@result[:title] || @result["title"] || "Untitled Recipe"}
    </h2>
    <p :if={!@saved} class="text-sm text-[color:var(--muted)] mb-4">
      {gettext("Nothing saved yet.")}
    </p>
    <section class="mb-4">
      <h3 class="font-medium text-[color:var(--text)] mb-2">{gettext("Ingredients")}</h3>
      <ul class="space-y-1">
        <li
          :for={ing <- @result[:ingredients] || @result["ingredients"] || []}
          class="text-sm text-[color:var(--text)]"
        >
          {ing[:name] || ing["name"] || ing}
        </li>
      </ul>
    </section>
    <section class="mb-6">
      <h3 class="font-medium text-[color:var(--text)] mb-2">{gettext("Instructions")}</h3>
      <p class="text-sm text-[color:var(--text)]">
        {@result[:instructions] || @result["instructions"]}
      </p>
    </section>
    <button
      :if={!@saved}
      phx-click="confirm"
      class="w-full rounded-xl bg-[color:var(--accent)] text-white py-3 font-semibold"
    >
      {gettext("Confirm & Save")}
    </button>
    <p :if={@saved} class="text-center text-[color:var(--accent)] font-semibold">
      {gettext("Saved to your recipe catalog.")}
    </p>
    """
  end

  defp render_review(%{class: :receipt} = assigns) do
    ~H"""
    <h2 class="text-xl font-semibold text-[color:var(--text)] mb-4">{gettext("Receipt")}</h2>
    <p
      :if={@result[:store_name] || @result["store_name"]}
      class="text-sm text-[color:var(--muted)] mb-4"
    >
      Store: {@result[:store_name] || @result["store_name"]}
    </p>
    <p :if={!@saved} class="text-sm text-[color:var(--muted)] mb-4">
      {gettext("Nothing saved yet.")}
    </p>
    <table class="w-full text-sm mb-6">
      <thead>
        <tr class="text-left text-[color:var(--muted)]">
          <th>Item</th>
          <th>Qty</th>
          <th>Price</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={item <- @result[:items] || @result["items"] || []}>
          <td>{item[:product_name] || item["product_name"]}</td>
          <td>{item[:quantity] || item["quantity"]}</td>
          <td>{item[:total_price] || item["total_price"]}</td>
        </tr>
      </tbody>
    </table>
    <button
      :if={!@saved}
      phx-click="confirm"
      class="w-full rounded-xl bg-[color:var(--accent)] text-white py-3 font-semibold"
    >
      {gettext("Confirm & Save")}
    </button>
    <p :if={@saved} class="text-center text-[color:var(--accent)] font-semibold">
      {gettext("Saved to costs.")}
    </p>
    """
  end

  defp render_review(%{class: :pantry_items} = assigns) do
    ~H"""
    <h2 class="text-xl font-semibold text-[color:var(--text)] mb-4">{gettext("Pantry Items")}</h2>
    <p :if={!@saved} class="text-sm text-[color:var(--muted)] mb-4">
      {gettext("Nothing saved yet.")}
    </p>
    <ul class="space-y-2 mb-6">
      <li :for={item <- @result || []} class="text-sm text-[color:var(--text)]">
        {item[:name] || item["name"]} — {item[:quantity] || item["quantity"]} {item[:unit] ||
          item["unit"]}
      </li>
    </ul>
    <button
      :if={!@saved}
      phx-click="confirm"
      class="w-full rounded-xl bg-[color:var(--accent)] text-white py-3 font-semibold"
    >
      {gettext("Confirm & Add to Pantry")}
    </button>
    <p :if={@saved} class="text-center text-[color:var(--accent)] font-semibold">
      {gettext("Added to pantry.")}
    </p>
    """
  end

  defp render_review(assigns) do
    ~H"""
    <p class="text-[color:var(--muted)]">{gettext("Unknown review type.")}</p>
    """
  end
end
