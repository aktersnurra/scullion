defmodule ToreWeb.Layouts do
  @moduledoc """
  Application layout + chrome (top nav, mobile bottom nav, flash group).
  """
  use ToreWeb, :html

  embed_templates "layouts/*"

  defp nav_items do
    [
      {"/", gettext("Home"), "nav-home"},
      {"/plan", gettext("Week"), "nav-week"},
      {"/inbox", gettext("Inbox"), "nav-inbox"},
      {"/recipes", gettext("Recipes"), "nav-recipes"},
      {"/shop", gettext("Shop"), "nav-shop"},
      {"/prep", gettext("Prep"), "nav-prep"},
      {"/deals", gettext("Deals"), "nav-deals"},
      {"/cooking", gettext("Cooking"), "nav-cooking"},
      {"/settings", gettext("Settings"), "nav-settings"}
    ]
  end

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: "/"
  attr :inbox_count, :integer, default: 0
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav_items, nav_items())

    ~H"""
    <header class="sticky top-0 z-40 hidden md:flex h-[var(--nav-height)] items-center justify-center bg-[var(--bg)]/80 backdrop-blur border-b border-[color:var(--border)]">
      <nav class="flex items-center gap-1">
        <.nav_link
          :for={{path, label, icon} <- @nav_items}
          path={path}
          current={@current_path}
          icon={icon}
          label={label}
          badge={badge_for(path, @inbox_count)}
        />
      </nav>
    </header>

    <main class="min-h-[calc(100vh-var(--nav-height))] px-4 py-4 md:px-6 md:py-6 pb-24 md:pb-6">
      {render_slot(@inner_block)}
    </main>

    <nav class="md:hidden fixed bottom-0 inset-x-0 z-40 grid grid-cols-10 bg-[var(--surface)] border-t border-[color:var(--border)]">
      <.bottom_link
        :for={{path, _label, icon} <- @nav_items}
        path={path}
        current={@current_path}
        icon={icon}
        badge={badge_for(path, @inbox_count)}
      />
    </nav>

    <.flash_group flash={@flash} />
    """
  end

  # Surface the pending-runs count on the inbox nav entry. nil = no badge.
  defp badge_for("/inbox", count) when is_integer(count) and count > 0, do: count
  defp badge_for(_, _), do: nil

  attr :path, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :badge, :integer, default: nil

  defp nav_link(assigns) do
    assigns = assign(assigns, :active?, active?(assigns.current, assigns.path))

    ~H"""
    <a
      href={@path}
      title={@label}
      aria-label={@label}
      data-active={if @active?, do: "true"}
      class={[
        "relative px-3 h-[var(--nav-height)] inline-flex items-center justify-center border-b-2 transition-colors",
        @active? && "text-[color:var(--accent)] border-[color:var(--accent)]",
        !@active? && "text-[color:var(--muted)] border-transparent hover:text-[var(--text)]"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <.nav_badge :if={@badge} count={@badge} />
    </a>
    """
  end

  attr :path, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  attr :badge, :integer, default: nil

  defp bottom_link(assigns) do
    assigns = assign(assigns, :active?, active?(assigns.current, assigns.path))

    ~H"""
    <a
      href={@path}
      data-active={if @active?, do: "true"}
      class={[
        "relative flex items-center justify-center h-14",
        @active? && "text-[color:var(--accent)]",
        !@active? && "text-[color:var(--muted)]"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <.nav_badge :if={@badge} count={@badge} />
    </a>
    """
  end

  attr :count, :integer, required: true

  defp nav_badge(assigns) do
    ~H"""
    <span class="absolute -top-0.5 -right-0.5 min-w-[1.1rem] h-[1.1rem] px-1 inline-flex items-center justify-center rounded-full bg-red-500 text-white text-[10px] font-semibold leading-none">
      {if @count > 99, do: "99+", else: @count}
    </span>
    """
  end

  defp active?(current, "/"), do: current == "/"
  defp active?(current, path), do: String.starts_with?(current, path)

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
