defmodule ToreWeb.SettingsLive do
  use ToreWeb, :live_view

  alias Tore.{Accounts, Handlers.PlanningHandler}

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    guidance = get_in(user.preferences || %{}, ["dietary_guidance"]) || ""
    {:ok, assign(socket, dietary_guidance: guidance, saved: false)}
  end

  def handle_event("save_guidance", %{"dietary_guidance" => value}, socket) do
    user = socket.assigns.current_user
    prefs = Map.put(user.preferences || %{}, "dietary_guidance", String.trim(value))

    case Accounts.update_preferences(user, %{preferences: prefs}) do
      {:ok, _updated} -> {:noreply, assign(socket, dietary_guidance: String.trim(value), saved: true)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("clear_guidance", _params, socket) do
    user = socket.assigns.current_user
    prefs = Map.put(user.preferences || %{}, "dietary_guidance", "")

    case Accounts.update_preferences(user, %{preferences: prefs}) do
      {:ok, _updated} -> {:noreply, assign(socket, dietary_guidance: "", saved: false)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("generate_plan", _params, socket) do
    user = socket.assigns.current_user
    guidance = get_in(user.preferences || %{}, ["dietary_guidance"])
    plan_id = "default"
    week_start = Date.utc_today() |> Date.beginning_of_week()

    Task.start(fn ->
      PlanningHandler.generate_plan(plan_id, week_start,
        mode: :from_catalog,
        dietary_guidance: guidance
      )
    end)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/settings"}>
    <.page max_width={:md}>
      <.card padded={false}>
        <header class="px-6 pt-6 pb-3">
          <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">{gettext("Settings")}</h1>
        </header>

        <section class="px-6 pt-3 pb-5 border-t border-[color:var(--hairline)]">
          <h2 class="uppercase tracking-wider text-[color:var(--subtle)] mb-3" style="font-size: var(--t-micro); font-weight: 600;">{gettext("Users")}</h2>
          <div :if={@current_user} class="flex items-center gap-3">
            <span class="size-9 rounded-full bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)] inline-flex items-center justify-center font-semibold" style="font-size: var(--t-meta);">
              {String.first(@current_user.name || "?")}
            </span>
            <div class="flex-1 min-w-0">
              <p class="font-medium text-[var(--text)]" style="font-size: var(--t-body);">{@current_user.name}</p>
              <p class="text-[color:var(--muted)] capitalize" style="font-size: var(--t-meta);">{@current_user.role}</p>
            </div>
            <button type="button" class="inline-flex items-center gap-1.5 text-[color:var(--accent)] hover:underline" style="font-size: var(--t-meta);">
              <.icon name="hero-plus" class="size-4" /> {gettext("Generate new code")}
            </button>
          </div>
        </section>

        <section class="px-6 pt-5 pb-5 border-t border-[color:var(--hairline)]">
          <h2 class="uppercase tracking-wider text-[color:var(--subtle)] mb-3" style="font-size: var(--t-micro); font-weight: 600;">{gettext("Device tokens")}</h2>
          <div class="flex items-center gap-3">
            <.icon name="hero-device-tablet" class="size-5 text-[color:var(--muted)] shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="font-medium" style="font-size: var(--t-body);">{gettext("Kitchen kiosk")}</p>
              <p class="text-[color:var(--accent)]" style="font-size: var(--t-meta);">{gettext("active")}</p>
            </div>
            <button type="button" class="text-[color:var(--danger)] hover:underline" style="font-size: var(--t-meta);">{gettext("Revoke")}</button>
          </div>
        </section>

        <section class="px-6 pt-5 pb-5 border-t border-[color:var(--hairline)]">
          <h2 class="uppercase tracking-wider text-[color:var(--subtle)] mb-3" style="font-size: var(--t-micro); font-weight: 600;">{gettext("Recipe generation")}</h2>
          <p class="text-[color:var(--muted)] mb-3" style="font-size: var(--t-meta);">{gettext("Dietary guidance injected into plan and recipe suggestion prompts.")}</p>
          <form phx-submit="save_guidance" class="flex flex-col gap-3">
            <textarea
              name="dietary_guidance"
              rows="3"
              placeholder={gettext("e.g. low carb, high protein, no gluten")}
              class="w-full rounded-lg border border-[color:var(--hairline)] bg-[color:var(--surface)] px-3 py-2 text-[var(--text)] placeholder:text-[color:var(--muted)] focus:outline-none focus:ring-2 focus:ring-[color:var(--accent)]"
              style="font-size: var(--t-body);"
            >{@dietary_guidance}</textarea>
            <div class="flex items-center gap-2">
              <.button type="submit" variant={:primary}>{gettext("Save")}</.button>
              <.button type="button" variant={:secondary} phx-click="clear_guidance">{gettext("Clear")}</.button>
              <span :if={@saved} class="text-[color:var(--accent)]" style="font-size: var(--t-meta);">{gettext("Saved")}</span>
            </div>
          </form>
        </section>

        <section class="px-6 pt-5 pb-6 border-t border-[color:var(--hairline)]">
          <h2 class="uppercase tracking-wider text-[color:var(--subtle)] mb-3" style="font-size: var(--t-micro); font-weight: 600;">{gettext("Jobs")}</h2>
          <div class="flex flex-wrap gap-2">
            <.button variant={:secondary}>{gettext("Run deal scrape")}</.button>
            <.button variant={:secondary} phx-click="generate_plan">{gettext("Generate plan")}</.button>
          </div>
        </section>
      </.card>
    </.page>
    </Layouts.app>
    """
  end
end
