defmodule ToreWeb.KioskCaptureLive do
  use ToreWeb, :live_view

  @llm Application.compile_env(:tore, :llm_client)

  @system_prompt "You are a cooking assistant on a kitchen kiosk. Answer cooking questions only (techniques, substitutions, timing, temperatures, ingredient questions). Do not modify the meal plan or grocery list. Keep answers concise and practical."

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], input: "", loading: false)}
  end

  def handle_event("send", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      messages = socket.assigns.messages ++ [%{role: "user", content: message}]
      send(self(), {:ask_llm, messages})
      {:noreply, assign(socket, messages: messages, input: "", loading: true)}
    end
  end

  def handle_info({:ask_llm, messages}, socket) do
    case @llm.chat(@system_prompt, messages) do
      {:ok, reply, _usage} ->
        updated = messages ++ [%{role: "assistant", content: reply}]
        {:noreply, assign(socket, messages: updated, loading: false)}

      {:error, _reason} ->
        updated = messages ++ [%{role: "assistant", content: "Sorry, something went wrong."}]
        {:noreply, assign(socket, messages: updated, loading: false)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-stone-950 text-white flex flex-col">
      <div class="flex items-center gap-4 px-6 py-4 border-b border-stone-800">
        <.link navigate="/kiosk" class="text-stone-400 text-2xl">←</.link>
        <h1 class="text-xl font-semibold">{gettext("Ask Tore")}</h1>
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-4 flex flex-col gap-4">
        <div
          :for={msg <- @messages}
          class={
            if msg.role == "user",
              do: "self-end bg-amber-600 rounded-2xl rounded-br-sm px-4 py-3 max-w-[80%]",
              else: "self-start bg-stone-800 rounded-2xl rounded-bl-sm px-4 py-3 max-w-[80%]"
          }
        >
          <p class="text-base leading-relaxed">{msg.content}</p>
        </div>
        <div :if={@loading} class="self-start bg-stone-800 rounded-2xl px-4 py-3">
          <p class="text-stone-400 text-sm">{gettext("Thinking…")}</p>
        </div>
      </div>

      <form phx-submit="send" class="flex gap-3 px-6 py-4 border-t border-stone-800">
        <input
          name="message"
          type="text"
          value={@input}
          placeholder={gettext("Ask a cooking question…")}
          class="flex-1 rounded-xl bg-stone-800 px-4 py-4 text-lg outline-none focus:ring-2 focus:ring-amber-500"
        />
        <button
          type="submit"
          class="rounded-xl bg-amber-500 text-stone-950 px-6 font-semibold text-lg min-h-14 active:bg-amber-400"
        >
          {gettext("Send")}
        </button>
      </form>
    </div>
    """
  end
end
