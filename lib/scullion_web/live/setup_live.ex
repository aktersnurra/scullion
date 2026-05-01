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
    <div class="min-h-screen flex items-center justify-center bg-gray-50">
      <div class="max-w-md w-full p-8 bg-white rounded-lg shadow">
        <h1 class="text-2xl font-bold mb-6">First Boot Setup</h1>
        <%= if @code do %>
          <p class="mb-4 text-gray-700">
            Your admin account has been created. Save this code — it won't be shown again.
          </p>
          <div class="text-3xl font-mono tracking-widest text-center py-6 bg-gray-100 rounded select-all">
            {@code}
          </div>
          <a href="/login" class="mt-6 block text-center text-blue-600 hover:underline">
            Go to login &rarr;
          </a>
        <% else %>
          <form phx-submit="submit">
            <label class="block mb-2 text-sm font-medium text-gray-700">Your name</label>
            <input
              type="text"
              name="name"
              value={@name}
              class="w-full border rounded px-3 py-2 mb-4 focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="e.g. Gustaf"
              autofocus
            />
            <%= if @error do %>
              <p class="text-red-500 text-sm mb-4">{@error}</p>
            <% end %>
            <button
              type="submit"
              class="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 font-medium"
            >
              Create admin account
            </button>
          </form>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_code(<<a::binary-size(4), b::binary-size(4), c::binary-size(4), d::binary-size(4)>>),
    do: "#{a} #{b} #{c} #{d}"

  defp format_code(code), do: code
end
