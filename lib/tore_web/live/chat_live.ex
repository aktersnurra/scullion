defmodule ToreWeb.ChatLive do
  use ToreWeb, :live_view

  alias Tore.Chat.ChatHandler

  @impl true
  def mount(_params, _session, socket) do
    if :ets.whereis(:chat_reviews) == :undefined do
      :ets.new(:chat_reviews, [:set, :public, :named_table])
    end

    socket =
      socket
      |> assign(messages: [], input: "", loading: false, processing_photos: false)
      |> allow_upload(:chat_photos, accept: ~w(.jpg .jpeg .png), max_entries: 5)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    text = String.trim(text)

    photo_binaries =
      consume_uploaded_entries(socket, :chat_photos, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    cond do
      photo_binaries != [] ->
        correlation_id = Ecto.UUID.generate()
        pid = self()

        Task.start(fn ->
          result = Tore.PhotoPipeline.process_uploads(photo_binaries, correlation_id)
          send(pid, {:pipeline_complete, result})
        end)

        {:noreply, assign(socket, :processing_photos, true)}

      text != "" ->
        messages = socket.assigns.messages ++ [%{role: :user, text: text}]
        send(self(), {:chat, text})
        {:noreply, assign(socket, messages: messages, input: "", loading: true)}

      true ->
        {:noreply, socket}
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
  def handle_info({:pipeline_complete, {:ok, results}}, socket) do
    new_messages =
      Enum.map(results, fn
        %{class: :unknown, status: :ambiguous} ->
          %{role: :assistant, text: "I wasn't sure what that photo showed. Could you tell me — is it a receipt, a recipe, or your fridge?"}

        %{class: :fridge, status: :ok, result: items} ->
          names = items |> Enum.map(& (&1[:name] || &1["name"])) |> Enum.take(5) |> Enum.join(", ")
          text = if names == "", do: "I can see your fridge but it looks empty.", else: "I can see #{names} in your fridge. Want me to suggest some recipes?"
          %{role: :assistant, text: text}

        %{class: class, status: :ok, result: result} ->
          review_id = Ecto.UUID.generate()
          :ets.insert(:chat_reviews, {review_id, %{class: class, result: result}})
          %{role: :assistant, review_card: true, class: class, review_id: review_id, text: "I found a #{class}."}

        %{class: class, status: :error} ->
          %{role: :assistant, text: "Something went wrong processing the #{class} photo."}
      end)

    {:noreply,
     socket
     |> assign(:processing_photos, false)
     |> update(:messages, &(&1 ++ new_messages))}
  end

  @impl true
  def handle_info({:pipeline_complete, {:error, _}}, socket) do
    {:noreply, assign(socket, :processing_photos, false)}
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
          <div :if={Map.get(msg, :review_card)} class="bg-[var(--surface)] border border-[color:var(--border)] rounded-2xl px-4 py-3 max-w-[80%]">
            <p class="text-sm text-[color:var(--text)] mb-2">{gettext("I found a")} {msg.class}.</p>
            <.link navigate={"/review/#{msg.class}/#{msg.review_id}"} class="text-sm text-[color:var(--accent)] font-semibold">
              {gettext("Review")} →
            </.link>
          </div>
          <div :if={!Map.get(msg, :review_card)} class={[
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
        <div :if={@processing_photos} class="flex justify-start">
          <div class="bg-[var(--surface)] border border-[color:var(--border)] rounded-2xl px-4 py-2.5">
            <span class="text-[color:var(--muted)] text-sm">{gettext("Processing photo…")}</span>
          </div>
        </div>
      </div>

      <div class="px-4 py-3 border-t border-[color:var(--border)]">
        <form phx-submit="send_message" class="flex flex-col gap-2">
          <div class="flex items-center gap-2">
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
          </div>
          <.live_file_input upload={@uploads.chat_photos} class="hidden" id="chat-photos-input" />
          <button type="button" onclick="document.getElementById('chat-photos-input').click()" class="text-xs text-[color:var(--muted)] flex items-center gap-1">
            <.icon name="hero-camera" class="size-3.5" /> {gettext("Attach photo")}
          </button>
        </form>
      </div>
    </div>
    """
  end
end
