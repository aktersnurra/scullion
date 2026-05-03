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

  attr :value, :string, required: true
  attr :locked, :boolean, required: true
  defp numpad_button(assigns) do
    ~H"""
    <button id={"digit-#{@value}"}
            phx-click={JS.push("digit", value: %{value: @value})}
            disabled={@locked}
            class="bg-white border border-gray-200 text-gray-800 text-xl font-semibold py-4 rounded-xl hover:bg-gray-50 active:bg-gray-100 disabled:opacity-40 shadow-sm">
      {@value}
    </button>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50" phx-window-keydown="keydown">
      <div class="w-full max-w-xs">
        <div class="text-center mb-8">
          <div class="inline-flex items-center gap-1 text-2xl font-bold text-gray-900">
            <span class="text-green-600">S</span>cullion
          </div>
          <p class="text-sm text-gray-400 mt-1">Enter your 16-digit code</p>
        </div>

        <%!-- Code display --%>
        <div class="bg-white rounded-2xl border border-gray-100 px-4 py-5 mb-4">
          <div class="flex justify-center items-center gap-3 font-mono">
            <%= for group <- digit_groups(@digits) do %>
              <div class="flex gap-1.5">
                <%= for d <- group do %>
                  <span class={["text-lg leading-none", d == :empty && "text-gray-200", d != :empty && "text-gray-800"]}>
                    {if d == :empty, do: "·", else: "●"}
                  </span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%= if @error do %>
          <p class="text-red-500 text-center text-sm mb-3 bg-red-50 rounded-xl py-2 px-3">{@error}</p>
        <% end %>

        <%!-- Numpad --%>
        <div class="grid grid-cols-3 gap-2">
          <.numpad_button value="1" locked={@locked} />
          <.numpad_button value="2" locked={@locked} />
          <.numpad_button value="3" locked={@locked} />
          <.numpad_button value="4" locked={@locked} />
          <.numpad_button value="5" locked={@locked} />
          <.numpad_button value="6" locked={@locked} />
          <.numpad_button value="7" locked={@locked} />
          <.numpad_button value="8" locked={@locked} />
          <.numpad_button value="9" locked={@locked} />

          <button phx-click="backspace" disabled={@locked}
                  class="bg-white border border-gray-200 text-gray-500 text-lg py-4 rounded-xl hover:bg-gray-50 active:bg-gray-100 disabled:opacity-40 shadow-sm">
            ⌫
          </button>

          <.numpad_button value="0" locked={@locked} />

          <button phx-click="submit" disabled={@locked or length(@digits) < 16}
                  class="bg-green-600 hover:bg-green-700 text-white text-lg py-4 rounded-xl disabled:opacity-40 shadow-sm font-medium">
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
