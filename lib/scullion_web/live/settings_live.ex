defmodule ScullionWeb.SettingsLive do
  use ScullionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
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

        <section class="px-6 pt-5 pb-6 border-t border-[color:var(--hairline)]">
          <h2 class="uppercase tracking-wider text-[color:var(--subtle)] mb-3" style="font-size: var(--t-micro); font-weight: 600;">{gettext("Jobs")}</h2>
          <div class="flex flex-wrap gap-2">
            <.button variant={:secondary}>{gettext("Run deal scrape")}</.button>
            <.button variant={:secondary}>{gettext("Generate plan")}</.button>
          </div>
        </section>
      </.card>
    </.page>
    </Layouts.app>
    """
  end
end
