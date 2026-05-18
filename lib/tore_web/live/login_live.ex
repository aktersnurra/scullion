defmodule ToreWeb.LoginLive do
  use ToreWeb, :live_view
  alias Tore.Accounts
  alias Tore.Accounts.{LoginToken, RateLimiter}

  def mount(_params, session, socket) do
    if session["user_id"] do
      {:ok, push_navigate(socket, to: "/")}
    else
      ip = peer_ip(socket)
      locked = rate_limit_state(ip)
      {:ok, assign(socket, digits: [], error: nil, ip: ip, locked: locked)}
    end
  end

  def handle_event("digit", %{"value" => d}, socket) when length(socket.assigns.digits) < 16 do
    {:noreply, assign(socket, digits: socket.assigns.digits ++ [d], error: nil)}
  end

  def handle_event("digit", _, socket), do: {:noreply, socket}

  def handle_event("backspace", _, socket) do
    {:noreply, assign(socket, digits: Enum.drop(socket.assigns.digits, -1), error: nil)}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    cond do
      key in ~w(0 1 2 3 4 5 6 7 8 9) ->
        handle_event("digit", %{"value" => key}, socket)

      key in ~w(Backspace Delete) ->
        handle_event("backspace", %{}, socket)

      key == "Enter" ->
        handle_event("submit", %{}, socket)

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("submit", _, socket) do
    %{digits: digits, ip: ip} = socket.assigns

    cond do
      length(digits) < 16 ->
        {:noreply, assign(socket, error: gettext("Enter all 16 digits"))}

      match?({:error, :locked, _}, RateLimiter.check(ip)) ->
        {:error, :locked, retry_after} = RateLimiter.check(ip)

        {:noreply,
         assign(socket,
           error: gettext("Too many attempts. Try again in %{n}s", n: retry_after),
           digits: [],
           locked: true
         )}

      true ->
        code = Enum.join(digits)

        case Accounts.authenticate(code) do
          {:ok, user} ->
            RateLimiter.record_success(ip)
            token = LoginToken.create(user.id)
            {:noreply, push_navigate(socket, to: "/login/session?t=#{token}")}

          {:error, :invalid_code} ->
            RateLimiter.record_failure(ip)
            locked = rate_limit_state(ip)

            error =
              if locked,
                do: gettext("Too many attempts. Try again later."),
                else: gettext("Invalid code")

            {:noreply, assign(socket, error: error, digits: [], locked: locked)}
        end
    end
  end

  attr :value, :string, required: true
  attr :locked, :boolean, required: true

  defp numpad_button(assigns) do
    ~H"""
    <button
      id={"digit-#{@value}"}
      phx-click={JS.push("digit", value: %{value: @value}) |> JS.focus(to: "#keypad-focus-trap")}
      disabled={@locked}
      tabindex="-1"
      class="h-16 bg-[var(--surface)] border border-[color:var(--border)] rounded-[var(--r-xl)] text-[var(--text)] font-semibold hover:bg-[color:var(--hairline)] active:bg-[color:var(--accent-soft)] disabled:opacity-40 shadow-[0_1px_2px_rgba(17,24,39,0.04)] transition-colors"
      style="font-size: 22px;"
    >
      {@value}
    </button>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, slots: digit_slots(assigns.digits))

    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-[var(--bg)] px-4 py-8">
      <input
        id="keypad-focus-trap"
        aria-label={gettext("Enter code")}
        autofocus
        phx-keydown="keydown"
        readonly
        class="sr-only"
        value=""
      />
      <div class="w-full max-w-sm">
        <div class="flex items-center justify-center mb-6">
          <img src="/images/logo.svg" alt="Tore" class="h-24 w-auto" />
        </div>

        <h1
          class="text-center font-semibold text-[var(--text)] mb-5"
          style="font-size: var(--t-h1); line-height: 1.2;"
        >
          {gettext("Enter your 16-digit code")}
        </h1>

        <div class="bg-[var(--surface)] border border-[color:var(--border)] rounded-[var(--r-xl)] py-3 px-4 mb-5 shadow-[0_1px_2px_rgba(17,24,39,0.04)] w-full overflow-hidden">
          <div
            class="flex items-center justify-between font-mono tabular-nums w-full"
            style="font-size: 16px;"
          >
            <div :for={{group, gi} <- Enum.with_index(@slots)} class="flex gap-1">
              <span
                :for={{d, di} <- Enum.with_index(group)}
                class={[
                  "inline-flex items-center justify-center w-4 h-7",
                  (d == :cursor or d == :empty) && "text-[color:var(--subtle)]",
                  is_binary(d) && "text-[var(--text)]"
                ]}
                data-pos={"#{gi}-#{di}"}
                data-digit-filled={if is_binary(d), do: "true"}
              >
                {cond do
                  is_binary(d) -> "*"
                  d == :cursor -> "·"
                  true -> "·"
                end}
              </span>
            </div>
          </div>
        </div>

        <p
          :if={@error}
          class="text-[color:var(--danger)] text-center mb-3 bg-red-50 rounded-[var(--r-lg)] py-2 px-3"
          style="font-size: var(--t-meta);"
        >
          {@error}
        </p>

        <div class="grid grid-cols-3 gap-3">
          <.numpad_button value="1" locked={@locked} />
          <.numpad_button value="2" locked={@locked} />
          <.numpad_button value="3" locked={@locked} />
          <.numpad_button value="4" locked={@locked} />
          <.numpad_button value="5" locked={@locked} />
          <.numpad_button value="6" locked={@locked} />
          <.numpad_button value="7" locked={@locked} />
          <.numpad_button value="8" locked={@locked} />
          <.numpad_button value="9" locked={@locked} />

          <button
            phx-click={JS.push("backspace") |> JS.focus(to: "#keypad-focus-trap")}
            disabled={@locked}
            tabindex="-1"
            aria-label={gettext("Backspace")}
            class="h-16 bg-[var(--surface)] border border-[color:var(--border)] rounded-[var(--r-xl)] text-[color:var(--muted)] hover:bg-[color:var(--hairline)] disabled:opacity-40 shadow-[0_1px_2px_rgba(17,24,39,0.04)] inline-flex items-center justify-center"
          >
            <.icon name="hero-backspace" class="size-5" />
          </button>

          <.numpad_button value="0" locked={@locked} />

          <button
            phx-click={JS.push("submit") |> JS.focus(to: "#keypad-focus-trap")}
            disabled={@locked or length(@digits) < 16}
            tabindex="-1"
            aria-label={gettext("Submit")}
            class="h-16 bg-[color:var(--accent)] hover:bg-[color:var(--accent-hover)] text-white rounded-[var(--r-xl)] disabled:opacity-40 shadow-[0_1px_2px_rgba(17,24,39,0.06)] inline-flex items-center justify-center"
          >
            <.icon name="hero-arrow-right" class="size-5" />
          </button>
        </div>

        <div class="mt-6 text-center">
          <a
            href="#"
            class="text-[color:var(--accent)] hover:underline"
            style="font-size: var(--t-meta);"
          >
            {gettext("Need help?")}
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp digit_slots(digits) do
    pos = length(digits)

    Enum.map(0..15, fn i ->
      cond do
        i < pos -> Enum.at(digits, i)
        i == pos and pos < 16 -> :cursor
        true -> :empty
      end
    end)
    |> Enum.chunk_every(4)
  end

  defp peer_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: addr} -> addr |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  defp rate_limit_state(ip) do
    match?({:error, :locked, _}, RateLimiter.check(ip))
  end
end
