defmodule ScullionWeb.SetupLive do
  use ScullionWeb, :live_view
  alias Scullion.Accounts

  def mount(_params, _session, socket) do
    if Accounts.setup_complete?() do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {:ok, assign(socket, name: "", code: nil, error: nil)}
    end
  end

  def handle_event("submit", %{"name" => name}, socket) do
    case Accounts.create_admin(String.trim(name)) do
      {:ok, {_user, code}} ->
        {:noreply, assign(socket, code: format_code(code), error: nil)}

      {:error, _changeset} ->
        {:noreply, assign(socket, error: "Name is required")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-[var(--bg)] px-4 py-8">
      <div class="w-full max-w-sm">
        <div class="flex items-center justify-center gap-2 mb-6">
          <.icon name="hero-cake" class="size-5 text-[color:var(--accent)]" />
          <span class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">Scullion</span>
        </div>

        <%= if @code do %>
          <h1 class="text-center font-semibold text-[var(--text)] mb-2" style="font-size: var(--t-h1);">
            You're all set
          </h1>
          <p class="text-center text-[color:var(--muted)] mb-5" style="font-size: var(--t-meta);">
            Save this 16-digit code — it won't be shown again.
          </p>
          <div class="bg-[var(--surface)] border border-[color:var(--border)] rounded-[var(--r-xl)] py-5 px-4 mb-5 shadow-[0_1px_2px_rgba(17,24,39,0.04)]">
            <div class="text-center font-mono tabular-nums text-[var(--text)] select-all" style="font-size: 22px; letter-spacing: 0.18em;">
              {@code}
            </div>
          </div>
          <.button variant={:primary} size={:lg} full>
            <a href="/login" class="inline-flex items-center gap-2">Go to login <.icon name="hero-arrow-right" class="size-4" /></a>
          </.button>
        <% else %>
          <h1 class="text-center font-semibold text-[var(--text)] mb-2" style="font-size: var(--t-h1);">
            Welcome to Scullion!
          </h1>
          <p class="text-center text-[color:var(--muted)] mb-5" style="font-size: var(--t-meta);">
            Let's create the first admin account.
          </p>

          <form phx-submit="submit" class="space-y-4">
            <div>
              <label class="block mb-1.5 text-[color:var(--muted)]" style="font-size: var(--t-meta); font-weight: 500;">
                What should we call you?
              </label>
              <input
                type="text"
                name="name"
                value={@name}
                placeholder="Your name"
                autofocus
                class="w-full h-11 px-3.5 bg-[var(--surface)] rounded-[var(--r-lg)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-body);"
              />
            </div>

            <p :if={@error} class="text-[color:var(--danger)] bg-red-50 rounded-[var(--r-lg)] py-2 px-3" style="font-size: var(--t-meta);">
              {@error}
            </p>

            <.button type="submit" variant={:primary} size={:lg} full>
              Create admin account
            </.button>
          </form>

          <div class="mt-5 bg-[color:var(--accent-soft)]/60 border border-[color:var(--border)] rounded-[var(--r-lg)] py-3 px-4 text-center text-[color:var(--accent-ink)]" style="font-size: var(--t-meta);">
            We'll generate a 16-digit code for you to save and use.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_code(
         <<a::binary-size(4), b::binary-size(4), c::binary-size(4), d::binary-size(4)>>
       ),
       do: "#{a} #{b} #{c} #{d}"

  defp format_code(code), do: code
end
