defmodule ToreWeb.CaptureLive do
  use ToreWeb, :live_view

  alias Tore.Capture.Conversation

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
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    text = String.trim(text)

    photo_binaries =
      consume_uploaded_entries(socket, :chat_photos, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    cond do
      photo_binaries != [] ->
        ctx = %{
          household_id: Tore.Household.get_household!().id,
          user_id: socket.assigns.current_user && socket.assigns.current_user.id
        }

        pid = self()

        Task.start(fn ->
          result = Tore.PhotoPipeline.process_uploads(photo_binaries, ctx)
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
    case Conversation.reply(text) do
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
    # Pull out the receipt batch first so multi-receipt uploads collapse to
    # one inbox-pointing reply instead of N "I parsed a receipt." bubbles.
    {receipt_results, other_results} =
      Enum.split_with(results, &match?(%{class: :receipt, status: :needs_review}, &1))

    receipt_message = receipt_inbox_message(receipt_results)
    other_messages = Enum.map(other_results, &message_for_result/1)

    new_messages = Enum.reject([receipt_message | other_messages], &is_nil/1)

    {:noreply,
     socket
     |> assign(:processing_photos, false)
     |> update(:messages, &(&1 ++ new_messages))}
  end

  defp receipt_inbox_message([]), do: nil

  defp receipt_inbox_message(receipts) do
    count = length(receipts)

    text =
      case count do
        1 -> gettext("I parsed a receipt. Review it in your inbox.")
        n -> gettext("I parsed %{n} receipts. Review them in your inbox.", n: n)
      end

    %{role: :assistant, inbox_link: true, text: text}
  end

  defp message_for_result(%{class: :unknown, status: :ambiguous}) do
    %{
      role: :assistant,
      text:
        gettext(
          "I wasn't sure what that photo showed. Could you tell me — is it a receipt, a recipe, or your fridge?"
        )
    }
  end

  defp message_for_result(%{class: :fridge, status: :ok, result: items}) do
    names = items |> Enum.map(&(&1[:name] || &1["name"])) |> Enum.take(5) |> Enum.join(", ")

    text =
      if names == "",
        do: gettext("I can see your fridge but it looks empty."),
        else: gettext("I can see %{names} in your fridge. Want me to suggest some recipes?",
          names: names
        )

    %{role: :assistant, text: text}
  end

  defp message_for_result(%{class: :pantry_items, status: :needs_review, run_stream_id: _sid}) do
    %{
      role: :assistant,
      inbox_link: true,
      text: gettext("I parsed your shelf photo. Review it in your inbox.")
    }
  end

  defp message_for_result(%{class: :pantry_items, status: :ok}) do
    %{role: :assistant, text: gettext("Added the pantry items from your photo.")}
  end

  defp message_for_result(%{class: class, status: :ok, result: result}) do
    review_id = Ecto.UUID.generate()
    :ets.insert(:chat_reviews, {review_id, %{class: class, result: result}})

    %{
      role: :assistant,
      review_card: true,
      class: class,
      review_id: review_id,
      text: gettext("I found a %{class}.", class: class)
    }
  end

  defp message_for_result(%{class: class, status: :error}) do
    %{role: :assistant, text: gettext("Something went wrong processing the %{class} photo.", class: class)}
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
        <div
          :for={msg <- @messages}
          class={[
            "flex",
            msg.role == :user && "justify-end",
            msg.role == :assistant && "justify-start"
          ]}
        >
          <div
            :if={Map.get(msg, :review_card)}
            class="bg-[var(--surface)] border border-[color:var(--border)] rounded-2xl px-4 py-3 max-w-[80%]"
          >
            <p class="text-sm text-[color:var(--text)] mb-2">{gettext("I found a")} {msg.class}.</p>
            <.link
              navigate={"/review/#{msg.class}/#{msg.review_id}"}
              class="text-sm text-[color:var(--accent)] font-semibold"
            >
              {gettext("Review")} →
            </.link>
          </div>
          <div
            :if={Map.get(msg, :inbox_link)}
            class="bg-[var(--surface)] border border-[color:var(--border)] rounded-2xl px-4 py-3 max-w-[80%]"
          >
            <p class="text-sm text-[color:var(--text)] mb-2">{msg.text}</p>
            <.link
              navigate={~p"/inbox"}
              class="text-sm text-[color:var(--accent)] font-semibold whitespace-nowrap"
            >
              {gettext("Open inbox")} →
            </.link>
          </div>
          <div
            :if={!Map.get(msg, :review_card) && !Map.get(msg, :inbox_link)}
            class={[
              "max-w-[80%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed",
              msg.role == :user && "bg-[color:var(--accent)] text-white",
              msg.role == :assistant &&
                "bg-[var(--surface)] border border-[color:var(--border)] text-[color:var(--text)]"
            ]}
          >
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
        <form phx-submit="send_message" phx-change="validate" class="flex flex-col gap-2">
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
          <div class="flex items-center gap-2 flex-wrap">
            <label
              for={@uploads.chat_photos.ref}
              class="text-xs text-[color:var(--muted)] flex items-center gap-1 cursor-pointer w-fit"
            >
              <.icon name="hero-camera" class="size-3.5" /> {gettext("Attach photo")}
            </label>
            <span
              :for={entry <- @uploads.chat_photos.entries}
              class="text-xs text-[color:var(--accent)]"
            >
              {entry.client_name} ({entry.progress}%)
            </span>
          </div>
          <.live_file_input upload={@uploads.chat_photos} class="hidden" />
        </form>
      </div>
    </div>
    """
  end
end
