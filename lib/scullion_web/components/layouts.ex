defmodule ScullionWeb.Layouts do
  @moduledoc """
  Application layout + chrome (top nav, mobile bottom nav, flash group).
  """
  use ScullionWeb, :html

  embed_templates "layouts/*"

  @nav_items [
    {"/", "Week", "hero-calendar-days"},
    {"/recipes", "Recipes", "hero-book-open"},
    {"/groceries", "Groceries", "hero-shopping-cart"},
    {"/prep", "Prep", "hero-fire"},
    {"/pantry", "Pantry", "hero-archive-box"},
    {"/costs", "Costs", "hero-banknotes"},
    {"/settings", "Settings", "hero-cog-6-tooth"}
  ]

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <header class="sticky top-0 z-40 hidden md:block h-[var(--nav-height)] px-6 bg-[var(--bg)]/80 backdrop-blur border-b border-[color:var(--border)]">
      <div class="relative h-full flex items-center justify-center">
        <nav class="flex items-center gap-1">
          <.nav_link :for={{path, label, icon} <- @nav_items} path={path} current={@current_path} icon={icon} label={label} />
        </nav>
        <a
          href="/logout"
          class="absolute right-0 top-1/2 -translate-y-1/2 text-[color:var(--muted)] hover:text-[var(--text)]"
          style="font-size: var(--t-meta);"
        >
          {gettext("Sign out")}
        </a>
      </div>
    </header>

    <main class="min-h-[calc(100vh-var(--nav-height))] px-4 py-4 md:px-6 md:py-6 pb-24 md:pb-6">
      {render_slot(@inner_block)}
    </main>

    <nav class="md:hidden fixed bottom-0 inset-x-0 z-40 grid grid-cols-7 bg-[var(--surface)] border-t border-[color:var(--border)]">
      <.bottom_link :for={{path, label, icon} <- @nav_items} path={path} current={@current_path} icon={icon}>
        {label}
      </.bottom_link>
    </nav>

    <.flash_group flash={@flash} />
    """
  end

  attr :path, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp nav_link(assigns) do
    assigns = assign(assigns, :active?, active?(assigns.current, assigns.path))

    ~H"""
    <a
      href={@path}
      title={@label}
      aria-label={@label}
      class={[
        "px-3 h-[var(--nav-height)] inline-flex items-center justify-center border-b-2 transition-colors",
        @active? && "text-[color:var(--accent)] border-[color:var(--accent)]",
        !@active? && "text-[color:var(--muted)] border-transparent hover:text-[var(--text)]"
      ]}
    >
      <.icon name={@icon} class="size-5" />
    </a>
    """
  end

  attr :path, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp bottom_link(assigns) do
    assigns = assign(assigns, :active?, active?(assigns.current, assigns.path))

    ~H"""
    <a
      href={@path}
      class={[
        "flex flex-col items-center justify-center gap-0.5 h-14",
        @active? && "text-[color:var(--accent)]",
        !@active? && "text-[color:var(--muted)]"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span style="font-size: 11px; font-weight: 500;">{render_slot(@inner_block)}</span>
    </a>
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
