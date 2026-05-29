defmodule ToreWeb.ChatLive do
  use ToreWeb, :live_view

  alias Tore.Chat.ChatHandler

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], input: "", loading: false)}
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      messages = socket.assigns.messages ++ [%{role: :user, text: text}]
      send(self(), {:chat, text})
      {:noreply, assign(socket, messages: messages, input: "", loading: true)}
    end
  end

  @impl true
  def handle_info({:chat, text}, socket) do
    case ChatHandler.handle_text(text) do
      {:ok, reply, _action} ->
        messages = socket.assigns.messages ++ [%{role: :assistant, text: reply}]
        {:noreply, assign(socket, messages: messages, loading: false)}

      {:error, _reason} ->
        messages =
          socket.assigns.messages ++
            [%{role: :assistant, text: "Sorry, I couldn't process that. Please try again."}]

        {:noreply, assign(socket, messages: messages, loading: false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-dvh bg-[var(--bg)]">
      <div class="flex items-center gap-3 px-4 py-3 border-b border-[color:var(--border)]">
        <.link navigate="/" class="text-[color:var(--muted)] hover:text-[color:var(--text)]">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <span class="font-semibold text-[color:var(--text)]">Ask Tore</span>
      </div>

      <div id="chat-messages" class="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        <div :for={msg <- @messages} class={["flex", msg.role == :user && "justify-end", msg.role == :assistant && "justify-start"]}>
          <div class={[
            "max-w-[80%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed",
            msg.role == :user && "bg-[color:var(--accent)] text-white",
            msg.role == :assistant && "bg-[var(--surface)] border border-[color:var(--border)] text-[color:var(--text)]"
          ]}>
            {msg.text}
          </div>
        </div>
        <div :if={@loading} class="flex justify-start">
          <div class="bg-[var(--surface)] border border-[color:var(--border)] rounded-2xl px-4 py-2.5">
            <span class="text-[color:var(--muted)] text-sm">{gettext("Thinking…")}</span>
          </div>
        </div>
      </div>

      <div class="px-4 py-3 border-t border-[color:var(--border)]">
        <form phx-submit="send_message" class="flex items-center gap-2">
          <input
            type="text"
            name="message"
            value={@input}
            placeholder={gettext("Ask anything about meals, groceries…")}
            autocomplete="off"
            class="flex-1 rounded-full border border-[color:var(--border)] bg-[var(--surface)] px-4 py-2.5 text-sm text-[color:var(--text)] placeholder:text-[color:var(--muted)] focus:outline-none"
          />
          <button
            type="submit"
            disabled={@loading}
            class="flex-shrink-0 w-10 h-10 rounded-full bg-[color:var(--accent)] flex items-center justify-center disabled:opacity-40"
          >
            <.icon name="hero-paper-airplane" class="size-4 text-white" />
          </button>
        </form>
      </div>
    </div>
    """
  end
end
