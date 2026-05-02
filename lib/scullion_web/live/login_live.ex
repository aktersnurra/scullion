defmodule ScullionWeb.LoginLive do
  use ScullionWeb, :live_view
  alias Scullion.Accounts
  alias Scullion.Accounts.{LoginToken, RateLimiter}

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

  def handle_event("submit", _, socket) do
    %{digits: digits, ip: ip} = socket.assigns

    cond do
      length(digits) < 16 ->
        {:noreply, assign(socket, error: "Enter all 16 digits")}

      match?({:error, :locked, _}, RateLimiter.check(ip)) ->
        {:error, :locked, retry_after} = RateLimiter.check(ip)

        {:noreply,
         assign(socket,
           error: "Too many attempts. Try again in #{retry_after}s",
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
            error = if locked, do: "Too many attempts. Try again later.", else: "Invalid code"
            {:noreply, assign(socket, error: error, digits: [], locked: locked)}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-900">
      <div class="w-full max-w-xs">
        <h1 class="text-white text-2xl font-bold text-center mb-8">Scullion</h1>

        <%!-- Code display --%>
        <div class="flex justify-center gap-3 mb-8 font-mono text-2xl">
          <%= for group <- digit_groups(@digits) do %>
            <div class="flex gap-1">
              <%= for d <- group do %>
                <span class="w-6 text-center text-white">
                  {if d == :empty, do: "·", else: "●"}
                </span>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @error do %>
          <p class="text-red-400 text-center text-sm mb-4">{@error}</p>
        <% end %>

        <%!-- Numpad --%>
        <div class="grid grid-cols-3 gap-3">
          <%= for n <- [1, 2, 3, 4, 5, 6, 7, 8, 9] do %>
            <button
              phx-click="digit"
              phx-value-value={Integer.to_string(n)}
              disabled={@locked}
              class="bg-gray-700 text-white text-2xl font-bold py-4 rounded-lg hover:bg-gray-600 active:bg-gray-500 disabled:opacity-40"
            >
              {n}
            </button>
          <% end %>

          <button
            phx-click="backspace"
            disabled={@locked}
            class="bg-gray-700 text-white text-xl py-4 rounded-lg hover:bg-gray-600 active:bg-gray-500 disabled:opacity-40"
          >
            ⌫
          </button>

          <button
            phx-click="digit"
            phx-value-value="0"
            disabled={@locked}
            class="bg-gray-700 text-white text-2xl font-bold py-4 rounded-lg hover:bg-gray-600 active:bg-gray-500 disabled:opacity-40"
          >
            0
          </button>

          <button
            phx-click="submit"
            disabled={@locked or length(@digits) < 16}
            class="bg-blue-600 text-white text-xl py-4 rounded-lg hover:bg-blue-500 active:bg-blue-400 disabled:opacity-40"
          >
            ↵
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp digit_groups(digits) do
    filled = Enum.map(digits, fn _ -> :filled end)
    padded = filled ++ List.duplicate(:empty, 16 - length(filled))
    Enum.chunk_every(padded, 4)
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
