defmodule ToreWeb.InboxLive do
  @moduledoc """
  Pending-work queue. Lists every `:needs_user` run for the household, newest
  first. Each row shows the original photo (the "ground truth" for what's
  being asked of the user), a short label, and time ago. Tap → /runs/:stream_id.

  Refreshes live via PubSub on the `harness:household:<id>` topic so cards
  appear as new runs land and disappear as they commit / discard / TTL-expire.
  """

  use ToreWeb, :live_view

  alias Tore.Harness.Projector
  alias Tore.Harness.Run.State
  alias Tore.Storage.RunPhotos

  @impl true
  def mount(_params, _session, socket) do
    household_id = household_id(socket)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tore.PubSub, "harness:household:#{household_id}")
    end

    {:ok, assign(socket, runs: Projector.list_pending(household_id))}
  end

  @impl true
  def handle_info({:run_state_changed, _stream_id, _state}, socket) do
    {:noreply, assign(socket, runs: Projector.list_pending(household_id(socket)))}
  end

  # Toast hook is attached by Live.Auth — ignore non-toast harness events here.
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/inbox"}>
      <div class="max-w-2xl mx-auto px-4 py-6">
        <header class="mb-6">
          <h1 class="text-2xl font-semibold text-[color:var(--text)]">
            {gettext("Inbox")}
          </h1>
          <p :if={@runs != []} class="mt-1 text-sm text-[color:var(--muted)]">
            {gettext("Things Tore needs you to confirm before applying.")}
          </p>
        </header>

        <%= if @runs == [] do %>
          <div class="rounded-2xl border border-dashed border-[color:var(--border)] bg-[var(--surface)] px-6 py-12 text-center">
            <p class="text-[color:var(--text)] font-medium mb-1">
              {gettext("All caught up.")}
            </p>
            <p class="text-sm text-[color:var(--muted)] mb-4">
              {gettext("Drop a receipt or photo in capture and it'll land here.")}
            </p>
            <.link
              navigate={~p"/capture"}
              class="inline-flex items-center gap-1 text-sm text-[color:var(--accent)] font-semibold"
            >
              {gettext("Go to capture")} <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          </div>
        <% else %>
          <ul class="space-y-2">
            <li :for={run <- @runs}>
              <.link
                navigate={~p"/runs/#{run.stream_id}"}
                class="flex items-center gap-3 rounded-2xl border border-[color:var(--border)] bg-[var(--surface)] p-3 hover:bg-[color:var(--accent-soft)]/40 transition-colors"
              >
                <.thumbnail image_path={image_path_of(run)} />

                <div class="flex-1 min-w-0">
                  <p class="text-[color:var(--text)] font-medium truncate">
                    {label_for(run)}
                  </p>
                  <p class="text-xs text-[color:var(--muted)]">
                    {time_ago(run.opened_at)}
                  </p>
                </div>

                <.icon
                  name="hero-chevron-right"
                  class="size-4 text-[color:var(--muted)] shrink-0"
                />
              </.link>
            </li>
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp thumbnail(%{image_path: nil} = assigns) do
    ~H"""
    <div class="size-12 rounded-lg bg-[color:var(--accent-soft)] inline-flex items-center justify-center shrink-0">
      <.icon name="hero-document-text" class="size-5 text-[color:var(--accent-ink)]" />
    </div>
    """
  end

  defp thumbnail(assigns) do
    assigns = assign(assigns, :url, RunPhotos.url(assigns.image_path))

    ~H"""
    <img
      src={@url}
      alt=""
      class="size-12 rounded-lg object-cover bg-[color:var(--accent-soft)] shrink-0"
      loading="lazy"
    />
    """
  end

  defp image_path_of(%State.NeedsUser{input: %{image_path: path}}) when is_binary(path), do: path
  defp image_path_of(_), do: nil

  defp label_for(%State.NeedsUser{kind: "receipt_ingestion_run"} = run) do
    case Enum.find(run.artifacts, &match?(%Tore.Harness.Artifact.CostEntry{}, &1)) do
      %{store_name: name} when is_binary(name) and name != "" ->
        items = items_count(run)
        "#{name} — #{items} #{gettext("items")}"

      _ ->
        "#{gettext("Receipt")} — #{items_count(run)} #{gettext("items")}"
    end
  end

  defp label_for(%State.NeedsUser{kind: "pantry_belief_update_run"} = run) do
    "#{gettext("Pantry update")} — #{items_count(run)} #{gettext("items")}"
  end

  defp label_for(%State.NeedsUser{kind: kind}), do: kind

  defp items_count(run) do
    Enum.find_value(run.artifacts, 0, fn
      %Tore.Harness.Artifact.PantryBeliefUpdate{items: items} -> length(items)
      %Tore.Harness.Artifact.CostEntry{line_items: items} -> length(items)
      _ -> nil
    end)
  end

  defp time_ago(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> gettext("just now")
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h"
      true -> "#{div(seconds, 86_400)}d"
    end
  end

  defp time_ago(_), do: ""

  defp household_id(socket), do: socket.assigns.current_user.household_id || 1
end
