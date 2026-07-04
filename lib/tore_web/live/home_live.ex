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
       plan_id: plan_id,
       today_key: today_key,
       tonight_recipe: tonight_recipe,
       recipes_by_id: recipes_by_id,
       home_notes: home_notes
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/">
      <%!-- Counter notes for home surface --%>
      <div :if={@home_notes != []} class="mb-4 flex flex-col gap-2">
        <div
          :for={note <- @home_notes}
          class="rounded-lg px-4 py-3 bg-[var(--surface)] border border-[color:var(--border)] text-sm text-[color:var(--text)]"
        >
          {note.body}
        </div>
      </div>

      <.link
        :if={@inbox_count > 0}
        navigate={~p"/inbox"}
        data-role="review-pill"
        class="inline-flex items-center gap-2 px-4 h-9 rounded-full border border-[color:var(--border)] bg-[var(--surface)] text-sm text-[var(--text)] mb-4"
      >
        {ngettext("%{count} to review", "%{count} to review", @inbox_count, count: @inbox_count)}
      </.link>

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
     |> assign(tonight_recipe: tonight_recipe)
     |> put_flash(:info, gettext("Slot cleared — pick something from the planner."))}
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
