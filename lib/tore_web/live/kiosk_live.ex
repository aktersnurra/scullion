defmodule ToreWeb.KioskLive do
  use ToreWeb, :live_view

  alias Tore.{Recipes, Handlers.PlanningHandler}

  @days ~w[mon tue wed thu fri sat sun]

  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = week_start(today)
    plan_id = plan_id(week_start)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tore.PubSub, "plan")
    end

    {:ok, plan_state} = PlanningHandler.load_plan(plan_id)
    recipes = Recipes.list()
    recipes_by_id = Map.new(recipes, &{&1.id, &1})

    tonight_slot_key = "#{Enum.at(@days, Date.day_of_week(today) - 1)}_dinner"
    tonight_slot = Map.get(plan_state.slots, tonight_slot_key)

    tonight_recipe =
      if tonight_slot && tonight_slot.recipe_id && !tonight_slot.skipped,
        do: Map.get(recipes_by_id, tonight_slot.recipe_id)

    upcoming = upcoming_days(today, week_start, plan_state, recipes_by_id)

    {:ok,
     assign(socket,
       today: today,
       week_start: week_start,
       plan_id: plan_id,
       plan_state: plan_state,
       recipes_by_id: recipes_by_id,
       tonight_slot_key: tonight_slot_key,
       tonight_slot: tonight_slot,
       tonight_recipe: tonight_recipe,
       upcoming: upcoming,
       pantry_input: nil,
       flash_msg: nil
     )}
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, assign(socket, flash_msg: nil)}
  end

  def handle_info({:events, _events}, socket) do
    {:ok, plan_state} = PlanningHandler.load_plan(socket.assigns.plan_id)
    tonight_slot = Map.get(plan_state.slots, socket.assigns.tonight_slot_key)

    tonight_recipe =
      if tonight_slot && tonight_slot.recipe_id && !tonight_slot.skipped,
        do: Map.get(socket.assigns.recipes_by_id, tonight_slot.recipe_id)

    upcoming =
      upcoming_days(
        socket.assigns.today,
        socket.assigns.week_start,
        plan_state,
        socket.assigns.recipes_by_id
      )

    {:noreply,
     assign(socket,
       plan_state: plan_state,
       tonight_slot: tonight_slot,
       tonight_recipe: tonight_recipe,
       upcoming: upcoming
     )}
  end

  def handle_event("swap_tonight", _params, socket) do
    case PlanningHandler.skip_meal(socket.assigns.plan_id, socket.assigns.tonight_slot_key) do
      {:ok, _events} ->
        {:noreply, flash(socket, "Tonight's meal swapped.")}

      {:error, _reason} ->
        {:noreply, flash(socket, "Could not swap — no meal assigned.")}
    end
  end

  def handle_event("cooked_it", _params, socket) do
    {:noreply, flash(socket, "Marked as done!")}
  end

  def handle_event("open_pantry_input", _params, socket) do
    {:noreply, assign(socket, pantry_input: "")}
  end

  def handle_event("submit_pantry", %{"item" => item}, socket) do
    item = String.trim(item)
    msg = if item != "", do: "Noted: out of #{item}.", else: nil
    {:noreply, assign(socket, pantry_input: nil, flash_msg: msg)}
  end

  defp flash(socket, msg) do
    Process.send_after(self(), :clear_flash, 3000)
    assign(socket, flash_msg: msg)
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp plan_id(week_start), do: "plan:#{Date.to_iso8601(week_start)}"

  defp upcoming_days(today, week_start, plan_state, recipes_by_id) do
    @days
    |> Enum.with_index()
    |> Enum.map(fn {day, i} ->
      date = Date.add(week_start, i)
      slot_key = "#{day}_dinner"
      slot = Map.get(plan_state.slots, slot_key)

      recipe =
        if slot && slot.recipe_id && !slot.skipped, do: Map.get(recipes_by_id, slot.recipe_id)

      %{day: day, date: date, slot_key: slot_key, recipe: recipe}
    end)
    |> Enum.reject(fn %{date: d} -> d == today end)
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-stone-950 text-white flex flex-col p-6 gap-6">
      <section class="flex flex-col gap-3">
        <p class="text-stone-400 text-lg uppercase tracking-widest font-medium">
          {gettext("Tonight")}
        </p>
        <h1 :if={@tonight_recipe} class="text-5xl font-bold leading-tight">
          {@tonight_recipe.title}
        </h1>
        <h1 :if={!@tonight_recipe} class="text-5xl font-bold leading-tight text-stone-500">
          {gettext("No meal planned")}
        </h1>
        <div class="rounded-2xl bg-stone-800 h-48 w-full flex items-center justify-center text-stone-600 text-sm">
          Photo
        </div>
      </section>

      <section class="flex flex-col gap-2">
        <p class="text-stone-400 text-sm uppercase tracking-widest font-medium">
          {gettext("Coming up")}
        </p>
        <div class="flex gap-3 overflow-x-auto pb-1">
          <div :for={day <- @upcoming} class="flex-shrink-0 rounded-xl bg-stone-800 px-4 py-3 w-32">
            <p class="text-stone-400 text-xs uppercase">{String.capitalize(day.day)}</p>
            <p class="text-sm font-medium mt-1 line-clamp-2">
              {if day.recipe, do: day.recipe.title, else: "—"}
            </p>
          </div>
        </div>
      </section>

      <section class="grid grid-cols-2 gap-4">
        <.link
          :if={@tonight_recipe}
          navigate={"/recipes/#{@tonight_recipe.id}"}
          class="rounded-2xl bg-amber-600 active:bg-amber-700 flex items-center justify-center text-center font-semibold text-lg min-h-20 px-4 py-4"
        >
          {gettext("What's the recipe?")}
        </.link>
        <div
          :if={!@tonight_recipe}
          class="rounded-2xl bg-amber-600 opacity-40 flex items-center justify-center text-center font-semibold text-lg min-h-20 px-4 py-4"
        >
          {gettext("What's the recipe?")}
        </div>

        <button
          phx-click="swap_tonight"
          class="rounded-2xl bg-sky-700 active:bg-sky-800 flex items-center justify-center text-center font-semibold text-lg min-h-20 px-4 py-4"
        >
          {gettext("Swap tonight")}
        </button>

        <button
          phx-click="cooked_it"
          class="rounded-2xl bg-emerald-700 active:bg-emerald-800 flex items-center justify-center text-center font-semibold text-lg min-h-20 px-4 py-4"
        >
          {gettext("I cooked it ✓")}
        </button>

        <button
          phx-click="open_pantry_input"
          class="rounded-2xl bg-stone-700 active:bg-stone-600 flex items-center justify-center text-center font-semibold text-lg min-h-20 px-4 py-4"
        >
          {gettext("We're out of…")}
        </button>
      </section>

      <form :if={@pantry_input != nil} phx-submit="submit_pantry" class="flex gap-3">
        <input
          name="item"
          type="text"
          autofocus
          placeholder={gettext("Item name…")}
          class="flex-1 rounded-xl bg-stone-800 px-4 py-4 text-lg outline-none focus:ring-2 focus:ring-amber-500"
        />
        <button type="submit" class="rounded-xl bg-amber-600 px-6 font-semibold text-lg">
          {gettext("Done")}
        </button>
      </form>

      <div
        :if={@flash_msg}
        class="fixed bottom-24 left-1/2 -translate-x-1/2 bg-stone-700 rounded-xl px-6 py-3 text-sm font-medium shadow-lg"
      >
        {@flash_msg}
      </div>

      <.link
        navigate="/kiosk/capture"
        class="fixed bottom-6 right-6 bg-amber-500 text-stone-950 rounded-full w-20 h-20 flex items-center justify-center shadow-xl text-sm font-bold text-center leading-tight active:bg-amber-400"
      >
        Ask Tore
      </.link>
    </div>
    """
  end
end
