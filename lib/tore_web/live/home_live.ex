defmodule ToreWeb.HomeLive do
  use ToreWeb, :live_view

  alias Tore.{Recipes, Planning, CounterNotes}

  @days ~w[mon tue wed thu fri sat sun]

  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = week_start(today)
    plan_id = plan_id(week_start)
    today_key = today_slot_key(today)

    {:ok, plan_state} = Planning.load_plan(plan_id)

    recipes = Recipes.list()
    recipes_by_id = Map.new(recipes, &{&1.id, &1})

    tonight_slot = Map.get(plan_state.slots, today_key)

    tonight_recipe =
      if tonight_slot && tonight_slot.recipe_id && !tonight_slot.skipped do
        Map.get(recipes_by_id, tonight_slot.recipe_id)
      end

    home_notes = CounterNotes.list_for_surface("home")

    {:ok,
     assign(socket,
       today: today,
       week_start: week_start,
       plan_id: plan_id,
       today_key: today_key,
       plan_state: plan_state,
       tonight_slot: tonight_slot,
       tonight_recipe: tonight_recipe,
       recipes_by_id: recipes_by_id,
       home_notes: home_notes
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} inbox_count={@inbox_count} current_path="/">
      <%!-- Counter notes for home surface --%>
      <div :if={@home_notes != []} class="mb-4 flex flex-col gap-2">
        <div
          :for={note <- @home_notes}
          class="rounded-lg px-4 py-3 bg-[var(--surface)] border border-[color:var(--border)] text-sm text-[color:var(--text)]"
        >
          {note.body}
        </div>
      </div>

      <%!-- Tonight card --%>
      <section class="mb-6">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-[color:var(--muted)] mb-3">
          {gettext("Tonight")}
        </h2>

        <div
          :if={@tonight_recipe}
          class="rounded-2xl bg-[var(--surface)] border border-[color:var(--border)] overflow-hidden"
        >
          <div class="w-full h-48 bg-[var(--border)] flex items-center justify-center text-[color:var(--muted)] text-sm">
            {gettext("No photo")}
          </div>
          <div class="p-4">
            <p class="text-xl font-semibold text-[color:var(--text)]">{@tonight_recipe.title}</p>
            <div class="mt-4 flex gap-3">
              <.link
                navigate={~p"/recipes"}
                class="flex-1 rounded-xl bg-[color:var(--accent)] text-white text-center py-3 text-sm font-semibold"
              >
                {gettext("Start cooking")}
              </.link>
              <button
                phx-click="something_else"
                class="flex-1 rounded-xl border border-[color:var(--border)] text-[color:var(--text)] py-3 text-sm font-semibold"
              >
                {gettext("Something else")}
              </button>
            </div>
          </div>
        </div>

        <div
          :if={!@tonight_recipe}
          class="rounded-2xl bg-[var(--surface)] border border-[color:var(--border)] p-6 text-center text-[color:var(--muted)] text-sm"
        >
          {gettext("Nothing planned for tonight")}
          <div class="mt-4">
            <.link navigate={~p"/plan"} class="text-[color:var(--accent)] font-semibold text-sm">
              {gettext("Open planner")}
            </.link>
          </div>
        </div>
      </section>

      <%!-- Week strip --%>
      <.week_strip
        plan_state={@plan_state}
        week_start={@week_start}
        today={@today}
        recipes_by_id={@recipes_by_id}
      />

      <%!-- FAB --%>
      <button
        phx-click="open_chat"
        class="fixed bottom-20 right-4 md:bottom-6 z-30 flex items-center gap-2 rounded-full bg-[color:var(--accent)] text-white px-5 py-3 shadow-lg text-sm font-semibold"
        aria-label={gettext("Ask Tore")}
      >
        <.icon name="hero-chat-bubble-left-ellipsis" class="size-5" />
        {gettext("Ask Tore")}
      </button>
    </Layouts.app>
    """
  end

  def handle_event("something_else", _params, socket) do
    %{plan_id: plan_id, today_key: today_key, recipes_by_id: recipes_by_id} = socket.assigns
    Planning.skip_meal(plan_id, today_key)
    {:ok, plan_state} = Planning.load_plan(plan_id)
    tonight_slot = Map.get(plan_state.slots, today_key)

    tonight_recipe =
      if tonight_slot && tonight_slot.recipe_id && !tonight_slot.skipped do
        Map.get(recipes_by_id, tonight_slot.recipe_id)
      end

    {:noreply,
     socket
     |> assign(plan_state: plan_state, tonight_slot: tonight_slot, tonight_recipe: tonight_recipe)
     |> put_flash(:info, gettext("Slot cleared — pick something from the planner."))}
  end

  def handle_event("open_chat", _params, socket) do
    {:noreply, push_navigate(socket, to: "/capture")}
  end

  attr :plan_state, :map, required: true
  attr :week_start, :any, required: true
  attr :today, :any, required: true
  attr :recipes_by_id, :map, required: true

  defp week_strip(assigns) do
    days = ~w[mon tue wed thu fri sat sun]
    dates = Enum.with_index(days, fn day, i -> {day, Date.add(assigns.week_start, i)} end)
    assigns = assign(assigns, :days_with_dates, dates)

    ~H"""
    <section>
      <h2 class="text-xs font-semibold uppercase tracking-wider text-[color:var(--muted)] mb-3">
        {gettext("This week")}
      </h2>
      <div class="flex gap-2 overflow-x-auto pb-2 -mx-4 px-4 snap-x">
        <.link
          :for={{day, date} <- @days_with_dates}
          navigate={~p"/plan"}
          class={[
            "snap-start shrink-0 w-24 rounded-xl border p-3 flex flex-col gap-1 transition-colors",
            date == @today && "border-[color:var(--accent)] bg-[var(--accent)]/10",
            date != @today && "border-[color:var(--border)] bg-[var(--surface)]"
          ]}
        >
          <span class={[
            "text-xs font-semibold uppercase tracking-wide",
            date == @today && "text-[color:var(--accent)]",
            date != @today && "text-[color:var(--muted)]"
          ]}>
            {day_abbr(date)}
          </span>
          <div class="w-full h-12 rounded-lg bg-[var(--border)]" />
          <span class="text-xs text-[color:var(--text)] truncate leading-tight">
            {slot_title(@plan_state, "#{day}_dinner", @recipes_by_id)}
          </span>
        </.link>
      </div>
    </section>
    """
  end

  defp slot_title(plan_state, slot_key, recipes_by_id) do
    slot = Map.get(plan_state.slots, slot_key)

    cond do
      is_nil(slot) || is_nil(slot.recipe_id) ->
        "—"

      slot.skipped ->
        gettext("Skipped")

      true ->
        recipe = Map.get(recipes_by_id, slot.recipe_id)
        if recipe, do: recipe.title, else: "—"
    end
  end

  defp day_abbr(date) do
    case Date.day_of_week(date) do
      1 -> gettext("Mon")
      2 -> gettext("Tue")
      3 -> gettext("Wed")
      4 -> gettext("Thu")
      5 -> gettext("Fri")
      6 -> gettext("Sat")
      7 -> gettext("Sun")
    end
  end

  defp today_slot_key(today) do
    dow = Date.day_of_week(today)
    day = Enum.at(@days, dow - 1)
    "#{day}_dinner"
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp plan_id(week_start), do: "plan:#{Date.to_iso8601(week_start)}"
end
