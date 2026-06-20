defmodule ToreWeb.RunReviewLive do
  @moduledoc """
  Editable card surface for a `:receipt_ingestion_run` in `:needs_user` state.

  Loads the run's CostEntry + PantryBeliefUpdate proposals, lets the user
  correct store/date/total/line-items, and confirms via
  `Tore.Harness.Orchestrator.commit_receipt/4` — which re-runs both verifiers
  before applying.
  """

  use ToreWeb, :live_view

  alias Tore.Harness.Artifact.{CostEntry, PantryBeliefUpdate}
  alias Tore.Harness.{Orchestrator, Run}
  alias Tore.Harness.Run.State

  @impl true
  def mount(%{"stream_id" => stream_id}, _session, socket) do
    case Run.load(stream_id) do
      {:ok, %State.NeedsUser{} = state} ->
        {cost, pantry} = extract_artifacts(state)

        socket =
          socket
          |> assign(:stream_id, stream_id)
          |> assign(:state, :needs_user)
          |> assign(:cost, cost)
          |> assign(:pantry, pantry)
          |> assign(:form_data, form_data_from(cost))
          |> assign(:error, nil)

        {:ok, socket}

      {:ok, %State.Applied{}} ->
        {:ok, assign(socket, stream_id: stream_id, state: :applied, error: nil)}

      {:ok, %State.Failed{failure_code: code}} ->
        {:ok, assign(socket, stream_id: stream_id, state: :failed, error: code)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Run not found.")
         |> push_navigate(to: ~p"/capture")}
    end
  end

  @impl true
  def handle_event("update", %{"receipt" => params}, socket) do
    {:noreply, assign(socket, :form_data, merge_form(socket.assigns.form_data, params))}
  end

  def handle_event("remove_item", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    items = List.delete_at(socket.assigns.form_data.line_items, idx)
    {:noreply, assign(socket, :form_data, %{socket.assigns.form_data | line_items: items})}
  end

  def handle_event("add_item", _params, socket) do
    items = socket.assigns.form_data.line_items ++ [blank_line_item()]
    {:noreply, assign(socket, :form_data, %{socket.assigns.form_data | line_items: items})}
  end

  defp blank_line_item do
    %{name: "", quantity: "", total_price: "", unit: "", category: nil}
  end

  def handle_event("confirm", _params, socket) do
    cost = build_cost(socket.assigns.cost, socket.assigns.form_data)
    pantry = build_pantry(socket.assigns.pantry, socket.assigns.form_data)
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    stream_id = socket.assigns.stream_id

    # Fire-and-forget: the commit takes ~3-8s (verifiers re-run + LLM
    # canonicaliser + atomic write). Kick it to Task.Supervisor and bounce
    # the user back to /capture immediately. The toast on completion lands
    # wherever they happen to be (PubSub topic "toasts:user:<id>").
    Task.Supervisor.start_child(Tore.TaskSupervisor, fn ->
      Orchestrator.commit_receipt(stream_id, cost, pantry, user_id)
      |> case do
        {:ok, _} ->
          broadcast_toast(user_id, :info, "Receipt saved.")

        {:error, {:verifier_failed, code, _}} ->
          broadcast_toast(user_id, :error, "Couldn't save receipt: #{code}.")

        {:error, reason} ->
          broadcast_toast(user_id, :error, "Couldn't save receipt: #{inspect(reason)}.")
      end
    end)

    {:noreply, push_navigate(socket, to: ~p"/capture")}
  end

  defp broadcast_toast(nil, _kind, _msg), do: :ok

  defp broadcast_toast(user_id, kind, message) do
    Phoenix.PubSub.broadcast(Tore.PubSub, "toasts:user:#{user_id}", {:toast, kind, message})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/runs/#{@stream_id}"}>
      <div class="max-w-2xl mx-auto px-4 py-6">
        <.link
          navigate={~p"/capture"}
          class="text-[color:var(--muted)] text-sm mb-4 inline-flex items-center gap-1"
        >
          <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to chat")}
        </.link>
        {render_body(assigns)}
      </div>
    </Layouts.app>
    """
  end

  defp render_body(%{state: :needs_user} = assigns) do
    ~H"""
    <h2 class="text-xl font-semibold text-[color:var(--text)] mb-4">
      {gettext("Review receipt")}
    </h2>
    <p class="text-sm text-[color:var(--muted)] mb-4">
      {gettext("Edit anything that looks wrong, then save. Costs and pantry update together.")}
    </p>

    <.error_banner :if={@error} code={@error} />

    <form phx-change="update" phx-submit="confirm" class="space-y-4">
      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="block text-xs text-[color:var(--muted)] mb-1">{gettext("Store")}</span>
          <input
            type="text"
            name="receipt[store_name]"
            value={@form_data.store_name}
            class="w-full rounded-lg border border-[color:var(--border)] bg-[var(--surface)] px-3 py-2 text-sm"
          />
        </label>
        <label class="block">
          <span class="block text-xs text-[color:var(--muted)] mb-1">{gettext("Date")}</span>
          <input
            type="date"
            name="receipt[date]"
            value={@form_data.date}
            class="w-full rounded-lg border border-[color:var(--border)] bg-[var(--surface)] px-3 py-2 text-sm"
          />
        </label>
      </div>
      <label class="block">
        <span class="block text-xs text-[color:var(--muted)] mb-1">{gettext("Total")}</span>
        <input
          type="text"
          inputmode="decimal"
          name="receipt[total]"
          value={@form_data.total}
          class="w-full rounded-lg border border-[color:var(--border)] bg-[var(--surface)] px-3 py-2 text-sm"
        />
      </label>

      <section>
        <h3 class="text-sm font-medium text-[color:var(--text)] mb-2">{gettext("Line items")}</h3>
        <p :if={sum_mismatch?(@form_data)} class="text-xs text-amber-600 mb-2">
          {gettext("Lines sum to")} {sum_display(@form_data)}; {gettext("receipt total")} {@form_data.total} — {gettext("looks off, is something missing?")}
        </p>
        <div class="space-y-2">
          <div
            :for={{item, idx} <- Enum.with_index(@form_data.line_items)}
            class="grid grid-cols-12 gap-2 items-center"
          >
            <input
              type="text"
              name={"receipt[line_items][#{idx}][name]"}
              value={item.name}
              placeholder="Item"
              class="col-span-6 rounded-lg border border-[color:var(--border)] bg-[var(--surface)] px-2 py-1.5 text-sm"
            />
            <input
              type="text"
              name={"receipt[line_items][#{idx}][quantity]"}
              value={item.quantity}
              placeholder="Qty"
              class="col-span-3 rounded-lg border border-[color:var(--border)] bg-[var(--surface)] px-2 py-1.5 text-sm"
            />
            <input
              type="text"
              name={"receipt[line_items][#{idx}][unit]"}
              value={item.unit}
              placeholder="Unit"
              class="col-span-2 rounded-lg border border-[color:var(--border)] bg-[var(--surface)] px-2 py-1.5 text-sm"
            />
            <input
              type="hidden"
              name={"receipt[line_items][#{idx}][total_price]"}
              value={item.total_price}
            />
            <button
              type="button"
              phx-click="remove_item"
              phx-value-index={idx}
              class="col-span-1 text-[color:var(--muted)] hover:text-red-500"
              aria-label="Remove"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </div>
        <p :if={@form_data.line_items == []} class="text-xs text-[color:var(--muted)] mt-2">
          {gettext("No items parsed. Nothing will be added to the pantry.")}
        </p>

        <button
          type="button"
          phx-click="add_item"
          class="mt-3 inline-flex items-center gap-1 text-sm text-[color:var(--accent)] hover:underline"
        >
          <.icon name="hero-plus" class="size-4" /> {gettext("Add item")}
        </button>
      </section>

      <button
        type="submit"
        class="w-full rounded-xl bg-[color:var(--accent)] text-white py-3 font-semibold"
      >
        {gettext("Save receipt")}
      </button>
    </form>
    """
  end

  defp render_body(%{state: :applied} = assigns) do
    ~H"""
    <p class="text-[color:var(--accent)] font-semibold">{gettext("Receipt already saved.")}</p>
    """
  end

  defp render_body(%{state: :failed} = assigns) do
    ~H"""
    <p class="text-red-500 font-semibold">{gettext("This receipt failed.")} {@error}</p>
    """
  end

  defp error_banner(assigns) do
    ~H"""
    <div class="mb-4 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-500">
      {gettext("Couldn't save:")} {@code}
    </div>
    """
  end

  defp extract_artifacts(%State.NeedsUser{artifacts: artifacts}) do
    cost = Enum.find(artifacts, &match?(%CostEntry{}, &1))
    pantry = Enum.find(artifacts, &match?(%PantryBeliefUpdate{}, &1))
    {cost, pantry}
  end

  defp form_data_from(%CostEntry{} = c) do
    %{
      store_name: c.store_name || "",
      date: Date.to_iso8601(c.date),
      total: decimal_to_str(c.total),
      line_items:
        Enum.map(c.line_items, fn it ->
          %{
            name: it.name || "",
            quantity: decimal_to_str(it[:quantity]),
            total_price: decimal_to_str(it[:total_price]),
            unit: it[:unit] || "",
            category: it[:category]
          }
        end)
    }
  end

  # Phoenix form params come back as %{"line_items" => %{"0" => %{...}, "1" => ...}}.
  # Re-key by integer index to preserve order even when the user removes an item.
  defp merge_form(current, params) do
    items =
      case params["line_items"] do
        nil ->
          current.line_items

        items when is_map(items) ->
          items
          |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
          |> Enum.map(fn {idx_str, attrs} ->
            existing = Enum.at(current.line_items, String.to_integer(idx_str), %{})

            %{
              name: attrs["name"] || existing[:name] || "",
              quantity: attrs["quantity"] || existing[:quantity] || "",
              total_price: attrs["total_price"] || existing[:total_price] || "",
              unit: attrs["unit"] || existing[:unit] || "",
              category: existing[:category]
            }
          end)
      end

    %{
      store_name: params["store_name"] || current.store_name,
      date: params["date"] || current.date,
      total: params["total"] || current.total,
      line_items: items
    }
  end

  defp build_cost(%CostEntry{} = c, form) do
    %CostEntry{
      c
      | store_name: form.store_name,
        date: parse_date(form.date, c.date),
        total: parse_decimal(form.total) || c.total,
        line_items:
          Enum.map(form.line_items, fn it ->
            %{
              name: String.trim(it.name),
              quantity: parse_decimal(it.quantity),
              unit: blank_to_nil(it[:unit]),
              total_price: parse_decimal(it.total_price),
              category: it[:category]
            }
          end)
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: String.trim(s)

  defp line_sum(form) do
    Enum.reduce(form.line_items, Decimal.new(0), fn it, acc ->
      case parse_decimal(it.total_price) do
        nil -> acc
        d -> Decimal.add(acc, d)
      end
    end)
  end

  defp sum_display(form), do: form |> line_sum() |> Decimal.to_string(:normal)

  defp sum_mismatch?(form) do
    case {parse_decimal(form.total), line_sum(form)} do
      {nil, _} ->
        false

      {_total, sum} ->
        if Decimal.equal?(sum, Decimal.new(0)) do
          false
        else
          diff = form.total |> parse_decimal() |> Decimal.sub(sum) |> Decimal.abs()
          Decimal.compare(diff, Decimal.new("1.00")) == :gt
        end
    end
  end

  defp build_pantry(%PantryBeliefUpdate{} = p, form) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Rebuild items from the (possibly edited) form so removed lines drop out
    # of the pantry write too. Keep provenance from the original proposal.
    items =
      Enum.map(form.line_items, fn it ->
        %{
          name: String.trim(it.name),
          change: :added,
          quantity: parse_decimal(it.quantity),
          unit: blank_to_nil(it[:unit]),
          category: it[:category],
          provenance: provenance_of(p),
          last_seen_at: now
        }
      end)
      |> Enum.reject(&(&1.name == ""))

    %PantryBeliefUpdate{items: items}
  end

  defp provenance_of(%PantryBeliefUpdate{items: [first | _]}), do: first.provenance
  defp provenance_of(_), do: "receipt"

  defp parse_date(str, fallback) do
    case Date.from_iso8601(str || "") do
      {:ok, d} -> d
      _ -> fallback
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(%Decimal{} = d), do: d

  defp parse_decimal(s) when is_binary(s) do
    case Decimal.parse(String.replace(s, ",", ".")) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp decimal_to_str(nil), do: ""
  defp decimal_to_str(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp decimal_to_str(n) when is_number(n), do: to_string(n)
  defp decimal_to_str(s) when is_binary(s), do: s
end
