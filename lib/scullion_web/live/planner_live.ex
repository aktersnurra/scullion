defmodule ScullionWeb.PlannerLive do
  use ScullionWeb, :live_view

  alias Scullion.{Recipes, Handlers.PlanningHandler, Handlers.GroceriesHandler}
  alias Phoenix.PubSub

  @days ~w[mon tue wed thu fri sat sun]

  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = week_start(today)
    plan_id = plan_id(week_start)

    if connected?(socket) do
      PubSub.subscribe(Scullion.PubSub, "plan")
    end

    {:ok, plan_state} = PlanningHandler.load_plan(plan_id)
    recipes = Recipes.list(sort: :alphabetical)

    {:ok,
     assign(socket,
       today: today,
       week_start: week_start,
       plan_id: plan_id,
       plan_state: plan_state,
       recipes: recipes,
       slot_action: nil
     )}
  end

  def handle_event("prev_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, -7)
    {:noreply, load_week(socket, week_start)}
  end

  def handle_event("next_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, 7)
    {:noreply, load_week(socket, week_start)}
  end

  def handle_event("open_slot", %{"slot_key" => sk}, socket) do
    slot = Map.get(socket.assigns.plan_state.slots, sk)

    initial = %{
      slot_key: sk,
      search: "",
      suggestions: [],
      loading_suggestions: true,
      selected_recipe_id: slot && slot.recipe_id,
      servings: (slot && slot.servings) || 4,
      leftover_days: MapSet.new(),
      skipped: (slot && slot.skipped) || false
    }

    parent = self()
    plan_id = socket.assigns.plan_id

    Task.start(fn ->
      case PlanningHandler.suggest_recipes_for_slot(plan_id, sk, limit: 5) do
        {:ok, suggestions} -> send(parent, {:suggestions_loaded, sk, suggestions})
        _ -> send(parent, {:suggestions_loaded, sk, []})
      end
    end)

    {:noreply, assign(socket, slot_action: initial)}
  end

  def handle_event("close_slot", _params, socket), do: {:noreply, assign(socket, slot_action: nil)}

  def handle_event("search_slot_recipes", %{"q" => q}, socket) do
    {:noreply, update_slot(socket, fn s -> %{s | search: q} end)}
  end

  def handle_event("pick_recipe", %{"id" => rid}, socket) do
    rid = String.to_integer(rid)
    recipe = Enum.find(socket.assigns.recipes, &(&1.id == rid))

    {:noreply,
     update_slot(socket, fn s ->
       %{s | selected_recipe_id: rid, servings: s.servings || (recipe && recipe.base_servings) || 4}
     end)}
  end

  def handle_event("inc_servings", _, socket) do
    {:noreply, update_slot(socket, fn s -> %{s | servings: min((s.servings || 1) + 1, 12)} end)}
  end

  def handle_event("dec_servings", _, socket) do
    {:noreply, update_slot(socket, fn s -> %{s | servings: max((s.servings || 1) - 1, 1)} end)}
  end

  def handle_event("toggle_leftover_day", %{"day" => d}, socket) do
    {:noreply,
     update_slot(socket, fn s ->
       new =
         if MapSet.member?(s.leftover_days, d),
           do: MapSet.delete(s.leftover_days, d),
           else: MapSet.put(s.leftover_days, d)

       %{s | leftover_days: new}
     end)}
  end

  def handle_event("toggle_skipped", _, socket) do
    {:noreply, update_slot(socket, fn s -> %{s | skipped: !s.skipped} end)}
  end

  def handle_event("save_slot", _, socket) do
    s = socket.assigns.slot_action
    plan_id = socket.assigns.plan_id

    cond do
      s.skipped ->
        # Skip requires the slot to exist; if there's nothing assigned, just close.
        slot = Map.get(socket.assigns.plan_state.slots, s.slot_key)
        if slot, do: PlanningHandler.skip_meal(plan_id, s.slot_key)
        {:noreply, assign(socket, slot_action: nil)}

      s.selected_recipe_id ->
        PlanningHandler.assign_with_leftovers(
          plan_id,
          s.slot_key,
          s.selected_recipe_id,
          s.servings,
          MapSet.to_list(s.leftover_days)
        )

        {:noreply, assign(socket, slot_action: nil)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("regenerate_suggestion", _, socket) do
    s = socket.assigns.slot_action
    plan_id = socket.assigns.plan_id
    parent = self()
    sk = s.slot_key

    Task.start(fn ->
      case PlanningHandler.suggest_recipes_for_slot(plan_id, sk, limit: 5, include_llm: true) do
        {:ok, suggestions} -> send(parent, {:suggestions_loaded, sk, suggestions})
        {:error, reason} -> send(parent, {:suggestion_error, sk, reason})
      end
    end)

    {:noreply, update_slot(socket, fn s -> %{s | loading_suggestions: true} end)}
  end

  def handle_event("remove_meal", %{"slot_key" => sk}, socket) do
    PlanningHandler.remove_recipe(socket.assigns.plan_id, sk)
    {:noreply, socket}
  end

  defp update_slot(socket, fun) do
    case socket.assigns.slot_action do
      nil -> socket
      s -> assign(socket, slot_action: fun.(s))
    end
  end

  defp rebuild_grocery_list(socket) do
    %{week_start: week_start} = socket.assigns
    {:ok, plan_state} = PlanningHandler.load_plan(socket.assigns.plan_id)

    recipe_ids =
      plan_state.slots
      |> Map.values()
      |> Enum.reject(&(&1.skipped || &1.leftover))
      |> Enum.map(& &1.recipe_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if recipe_ids != [] do
      GroceriesHandler.build_list(grocery_id(week_start), week_start, recipe_ids)
    end

    socket
  end

  def handle_info({:events, _events}, socket) do
    {:ok, plan_state} = PlanningHandler.load_plan(socket.assigns.plan_id)
    rebuild_grocery_list(socket)
    {:noreply, assign(socket, plan_state: plan_state)}
  end

  def handle_info({:suggestions_loaded, sk, suggestions}, socket) do
    case socket.assigns.slot_action do
      %{slot_key: ^sk} = s ->
        {:noreply,
         assign(socket, slot_action: %{s | suggestions: suggestions, loading_suggestions: false})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:suggestion_error, sk, reason}, socket) do
    case socket.assigns.slot_action do
      %{slot_key: ^sk} = s ->
        msg =
          case reason do
            :budget_exceeded -> "Monthly LLM budget reached"
            :cooldown -> "Please wait a moment before trying again"
            _ -> "Couldn't fetch a new suggestion"
          end

        {:noreply,
         socket
         |> put_flash(:error, msg)
         |> assign(slot_action: %{s | loading_suggestions: false})}

      _ ->
        {:noreply, socket}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        days: @days,
        week_end: Date.add(assigns.week_start, 6),
        week_number: week_number(assigns.week_start)
      )

    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/"}>
    <.page max_width={:md}>
      <header class="flex items-center justify-between gap-4 mb-5">
        <button
          type="button"
          phx-click="prev_week"
          class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"
          aria-label="Previous week"
        >
          <.icon name="hero-chevron-left" class="size-5" />
        </button>

        <div class="text-center">
          <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">This week</h1>
          <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">
            {plan_subtitle(@plan_state, @week_start, @week_end)}
          </p>
        </div>

        <button
          type="button"
          phx-click="next_week"
          class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"
          aria-label="Next week"
        >
          <.icon name="hero-chevron-right" class="size-5" />
        </button>
      </header>

      <.card padded={false}>
        <ul class="divide-y divide-[color:var(--hairline)]">
          <.day_row
            :for={{day, i} <- Enum.with_index(@days)}
            day={day}
            date={Date.add(@week_start, i)}
            today={@today}
            slot_key={"#{day}_dinner"}
            plan_state={@plan_state}
            recipes={@recipes}
            days={@days}
          />
        </ul>

        <p class="px-6 py-4 text-center text-[color:var(--subtle)]" style="font-size: var(--t-meta);">
          Swipe left to right to see other weeks
        </p>
      </.card>

      <.slot_modal
        :if={@slot_action}
        slot_action={@slot_action}
        plan_state={@plan_state}
        recipes={@recipes}
      />
    </.page>
    </Layouts.app>
    """
  end

  attr :day, :string, required: true
  attr :date, :any, required: true
  attr :today, :any, required: true
  attr :slot_key, :string, required: true
  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true
  attr :days, :list, required: true

  defp day_row(assigns) do
    slot = Map.get(assigns.plan_state.slots, assigns.slot_key)
    recipe = recipe_by_id(assigns.recipes, slot[:recipe_id])
    is_today = assigns.date == assigns.today
    assigns = assign(assigns, slot: slot, recipe: recipe, is_today: is_today)

    ~H"""
    <li class={[
      "grid grid-cols-[56px_80px_1fr_auto_auto] items-center gap-4 px-5 py-3 transition-colors group",
      @slot && @slot.skipped && "opacity-50"
    ]}>
      <button
        type="button"
        phx-click="open_slot"
        phx-value-slot_key={@slot_key}
        aria-label="Edit meal"
        class="contents text-left"
      >
        <div class="flex flex-col items-center">
          <div
            class={[
              "uppercase tracking-wide font-medium leading-none",
              !@is_today && "text-[color:var(--subtle)]",
              @is_today && "text-[color:var(--accent)]"
            ]}
            style="font-size: 11px;"
          >
            {Calendar.strftime(@date, "%a")}
          </div>
          <div
            class={[
              "font-semibold leading-none mt-1.5",
              @is_today && "text-[color:var(--accent)]",
              !@is_today && "text-[var(--text)]"
            ]}
            style="font-size: 22px;"
          >
            {Calendar.strftime(@date, "%-d")}
          </div>
          <div :if={@is_today} class="mt-1 text-[color:var(--accent)] font-medium leading-none" style="font-size: 11px;">
            Today
          </div>
        </div>

        <div class={[
          "h-[60px] w-20 rounded-[var(--r-lg)] overflow-hidden flex items-center justify-center text-[color:var(--subtle)]",
          @recipe && "bg-[color:var(--hairline)]",
          !@recipe && "bg-transparent border border-dashed border-[color:var(--border)]"
        ]}>
          <img :if={@recipe && @recipe.image_path} src={@recipe.image_path} alt="" class="h-full w-full object-cover" />
          <.icon :if={@recipe && !@recipe.image_path} name="hero-photo" class="size-6" />
          <.icon :if={!@recipe} name="hero-plus" class="size-5" />
        </div>

        <div class="min-w-0">
          <%= cond do %>
            <% @recipe -> %>
              <p class="font-semibold text-[var(--text)] truncate" style="font-size: var(--t-body);">
                {@recipe.title}
              </p>
              <div class="mt-1 flex items-center gap-3 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                <span :if={@slot.servings} class="inline-flex items-center gap-1">
                  <.icon name="hero-user-group" class="size-3.5" /> {@slot.servings} servings
                </span>
                <span :if={@slot.leftover} class="inline-flex items-center gap-1">
                  <.icon name="hero-arrow-uturn-right" class="size-3.5" /> Uses leftovers
                </span>
              </div>
            <% @slot && @slot.leftover -> %>
              <p class="text-[color:var(--muted)]" style="font-size: var(--t-body);">Leftovers</p>
            <% @slot && @slot.skipped -> %>
              <p class="text-[color:var(--subtle)]" style="font-size: var(--t-body);">Skipped</p>
            <% true -> %>
              <p class="text-[color:var(--subtle)]" style="font-size: var(--t-body);">— add a meal</p>
          <% end %>
        </div>

        <.chip :if={leftover_target(@plan_state, @days, @date) != nil} tone={:accent}>
          Leftovers for {leftover_target(@plan_state, @days, @date)}
        </.chip>
        <span :if={leftover_target(@plan_state, @days, @date) == nil}></span>
      </button>

      <%= if @slot && @slot.recipe_id do %>
        <button
          type="button"
          phx-click="remove_meal"
          phx-value-slot_key={@slot_key}
          data-confirm="Remove this meal?"
          aria-label="Remove meal"
          class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--subtle)] hover:text-[color:var(--danger)] hover:bg-[color:var(--hairline)] justify-self-end"
        >
          <.icon name="hero-ellipsis-horizontal" class="size-4" />
        </button>
      <% else %>
        <span class="size-9 inline-flex items-center justify-center text-[color:var(--muted)] justify-self-end">
          <.icon name="hero-chevron-right" class="size-5" />
        </span>
      <% end %>
    </li>
    """
  end

  # If this day has a meal AND the next day(s) consume leftovers from it, show
  # the chip with the consuming day name(s).
  defp leftover_target(plan_state, days, date) do
    weekday_idx = Date.day_of_week(date) - 1

    next =
      days
      |> Enum.with_index()
      |> Enum.drop(weekday_idx + 1)
      |> Enum.find(fn {d, _} ->
        slot = Map.get(plan_state.slots, "#{d}_dinner")
        slot && slot.leftover
      end)

    case next do
      {d, _} -> String.capitalize(d)
      nil -> nil
    end
  end

  attr :slot_action, :map, required: true
  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true

  defp slot_modal(assigns) do
    sa = assigns.slot_action

    suggested_ids = MapSet.new(sa.suggestions, & &1.recipe.id)

    other_recipes =
      assigns.recipes
      |> Enum.reject(&MapSet.member?(suggested_ids, &1.id))
      |> filter_recipes(sa.search)

    assigns =
      assign(assigns,
        suggested_ids: suggested_ids,
        other_recipes: other_recipes,
        days_after: days_after(sa.slot_key),
        save_disabled: !sa.skipped && is_nil(sa.selected_recipe_id)
      )

    ~H"""
    <div
      class="fixed inset-0 bg-black/30 z-50 flex items-end md:items-center justify-center p-4"
      phx-click="close_slot"
    >
      <div
        class="bg-[var(--surface)] w-full md:max-w-md max-h-[92vh] flex flex-col rounded-[var(--r-xl)] shadow-[0_6px_24px_rgba(17,24,39,0.18)] overflow-hidden"
        phx-click-away="close_slot"
        onclick="event.stopPropagation()"
      >
        <header class="flex items-center justify-between px-6 py-4 border-b border-[color:var(--hairline)] shrink-0">
          <h2 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">
            {slot_label(@slot_action.slot_key)}
          </h2>
          <.icon_button icon="hero-x-mark" label="Close" phx-click="close_slot" />
        </header>

        <div class={[
          "flex-1 overflow-y-auto px-6 pt-4 pb-4 space-y-5",
          @slot_action.skipped && "opacity-50 pointer-events-none"
        ]}>
          <form phx-change="search_slot_recipes">
            <div class="relative">
              <.icon name="hero-magnifying-glass" class="size-5 absolute left-3.5 top-1/2 -translate-y-1/2 text-[color:var(--subtle)]" />
              <input
                type="text"
                name="q"
                value={@slot_action.search}
                placeholder="Search recipes…"
                class="w-full h-11 pl-10 pr-3 bg-[var(--surface)] rounded-[var(--r-lg)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-body);"
              />
            </div>
          </form>

          <%= if @slot_action.search == "" do %>
            <section>
              <div class="flex items-center justify-between mb-2">
                <h3 class="uppercase tracking-wider text-[color:var(--subtle)]" style="font-size: var(--t-micro); font-weight: 600;">Suggested</h3>
                <button
                  type="button"
                  phx-click="regenerate_suggestion"
                  disabled={@slot_action.loading_suggestions}
                  class="inline-flex items-center gap-1 text-[color:var(--accent)] hover:underline disabled:opacity-40"
                  style="font-size: var(--t-meta);"
                >
                  <.icon name="hero-sparkles" class="size-3.5" /> Try another
                </button>
              </div>

              <%= if @slot_action.loading_suggestions and @slot_action.suggestions == [] do %>
                <p class="text-[color:var(--muted)] py-2" style="font-size: var(--t-meta);">Loading…</p>
              <% else %>
                <%= if @slot_action.suggestions == [] do %>
                  <p class="text-[color:var(--muted)] py-2" style="font-size: var(--t-meta);">No suggestions yet — pick from below.</p>
                <% else %>
                  <ul class="space-y-2">
                    <.recipe_pick_row :for={sug <- @slot_action.suggestions}
                      recipe={sug.recipe}
                      reasons={sug.reasons}
                      selected={@slot_action.selected_recipe_id == sug.recipe.id} />
                  </ul>
                <% end %>
              <% end %>
            </section>
          <% end %>

          <section>
            <h3 class="uppercase tracking-wider text-[color:var(--subtle)] mb-2" style="font-size: var(--t-micro); font-weight: 600;">
              <%= if @slot_action.search == "", do: "All recipes", else: "Results" %>
            </h3>
            <%= if @other_recipes == [] do %>
              <p class="text-[color:var(--muted)] py-2" style="font-size: var(--t-meta);">No recipes match.</p>
            <% else %>
              <ul class="space-y-2">
                <.recipe_pick_row :for={r <- @other_recipes}
                  recipe={r}
                  reasons={[]}
                  selected={@slot_action.selected_recipe_id == r.id} />
              </ul>
            <% end %>
          </section>
        </div>

        <footer class="border-t border-[color:var(--hairline)] px-6 py-4 space-y-4 shrink-0">
          <div class={[@slot_action.skipped && "opacity-50 pointer-events-none"]}>
            <div class="flex items-center justify-between">
              <span class="text-[color:var(--muted)]" style="font-size: var(--t-meta); font-weight: 500;">Portions</span>
              <div class="inline-flex items-center gap-3">
                <button type="button" phx-click="dec_servings"
                        class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] border border-[color:var(--border)] text-[var(--text)] hover:border-[color:var(--subtle)]"
                        aria-label="Fewer servings">
                  <.icon name="hero-minus" class="size-4" />
                </button>
                <span class="w-8 text-center font-semibold tabular-nums" style="font-size: var(--t-h2);">{@slot_action.servings}</span>
                <button type="button" phx-click="inc_servings"
                        class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] border border-[color:var(--border)] text-[var(--text)] hover:border-[color:var(--subtle)]"
                        aria-label="More servings">
                  <.icon name="hero-plus" class="size-4" />
                </button>
              </div>
            </div>

            <div :if={@days_after != [] and @slot_action.selected_recipe_id} class="mt-4">
              <p class="text-[color:var(--muted)] mb-2" style="font-size: var(--t-meta); font-weight: 500;">Leftovers for</p>
              <div class="flex flex-wrap gap-2">
                <button :for={d <- @days_after}
                  type="button"
                  phx-click="toggle_leftover_day"
                  phx-value-day={"#{d}_dinner"}
                  class={[
                    "h-8 px-3 rounded-[var(--r-pill)] transition-colors capitalize",
                    MapSet.member?(@slot_action.leftover_days, "#{d}_dinner") && "bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)]",
                    !MapSet.member?(@slot_action.leftover_days, "#{d}_dinner") && "bg-[color:var(--hairline)] text-[color:var(--muted)] hover:text-[var(--text)]"
                  ]}
                  style="font-size: var(--t-meta); font-weight: 500;"
                >
                  {String.capitalize(d)}
                </button>
              </div>
            </div>
          </div>

          <label class="flex items-center justify-between gap-3 cursor-pointer pt-3 border-t border-[color:var(--hairline)]">
            <span class="text-[var(--text)]" style="font-size: var(--t-body);">No dinner planned</span>
            <input
              type="checkbox"
              checked={@slot_action.skipped}
              phx-click="toggle_skipped"
              class="size-5 rounded border-[color:var(--border)] text-[color:var(--accent)] focus:ring-[color:var(--accent)]"
            />
          </label>

          <.button variant={:primary} size={:lg} full disabled={@save_disabled} phx-click="save_slot">
            Save
          </.button>
        </footer>
      </div>
    </div>
    """
  end

  attr :recipe, :any, required: true
  attr :reasons, :list, default: []
  attr :selected, :boolean, default: false

  defp recipe_pick_row(assigns) do
    total = (assigns.recipe.prep_time_minutes || 0) + (assigns.recipe.cook_time_minutes || 0)
    assigns = assign(assigns, total_min: total)

    ~H"""
    <li>
      <button
        type="button"
        phx-click="pick_recipe"
        phx-value-id={@recipe.id}
        class={[
          "w-full flex items-start gap-3 p-3 rounded-[var(--r-lg)] border text-left transition-colors",
          @selected && "border-[color:var(--accent)] bg-[color:var(--accent-soft)]/40",
          !@selected && "border-[color:var(--border)] hover:border-[color:var(--subtle)]"
        ]}
      >
        <div class="size-12 shrink-0 rounded-[var(--r-md)] overflow-hidden bg-[color:var(--hairline)] flex items-center justify-center text-[color:var(--subtle)]">
          <img :if={@recipe.image_path} src={@recipe.image_path} alt="" class="h-full w-full object-cover" />
          <.icon :if={!@recipe.image_path} name="hero-photo" class="size-5" />
        </div>
        <div class="flex-1 min-w-0">
          <p class="font-semibold text-[var(--text)] truncate" style="font-size: var(--t-body);">{@recipe.title}</p>
          <p class="mt-0.5 text-[color:var(--muted)] truncate" style="font-size: var(--t-meta);">
            <%= if @reasons != [] do %>
              {Enum.join(@reasons, " · ")}
            <% else %>
              <%= if @total_min > 0, do: "#{@total_min} min", else: "" %><%= if @recipe.base_servings, do: " · #{@recipe.base_servings} portions", else: "" %>
            <% end %>
          </p>
        </div>
      </button>
    </li>
    """
  end

  defp load_week(socket, week_start) do
    plan_id = plan_id(week_start)
    {:ok, plan_state} = PlanningHandler.load_plan(plan_id)
    assign(socket, week_start: week_start, plan_id: plan_id, plan_state: plan_state)
  end

  defp recipe_by_id(_recipes, nil), do: nil
  defp recipe_by_id(recipes, id), do: Enum.find(recipes, &(&1.id == id))

  @full_day_names %{
    "mon" => "Monday",
    "tue" => "Tuesday",
    "wed" => "Wednesday",
    "thu" => "Thursday",
    "fri" => "Friday",
    "sat" => "Saturday",
    "sun" => "Sunday"
  }

  defp slot_label(slot_key) do
    [day, meal] = String.split(slot_key, "_", parts: 2)
    "#{Map.get(@full_day_names, day, String.capitalize(day))} · #{String.capitalize(meal)}"
  end

  defp days_after(slot_key) do
    [day, _meal] = String.split(slot_key, "_", parts: 2)
    days = ~w[mon tue wed thu fri sat sun]
    idx = Enum.find_index(days, &(&1 == day))
    if idx, do: Enum.drop(days, idx + 1), else: []
  end

  defp filter_recipes(recipes, ""), do: recipes

  defp filter_recipes(recipes, q) do
    q = String.downcase(q)
    Enum.filter(recipes, &String.contains?(String.downcase(&1.title), q))
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp week_number(date) do
    {_y, w} = :calendar.iso_week_number({date.year, date.month, date.day})
    w
  end

  defp plan_subtitle(plan_state, week_start, week_end) do
    range = "#{Calendar.strftime(week_start, "%b %-d")} – #{Calendar.strftime(week_end, "%b %-d")}"

    meals =
      plan_state.slots
      |> Map.values()
      |> Enum.count(fn s -> s.recipe_id && !s.skipped end)

    if meals > 0, do: "#{range} · #{meals} meals planned", else: range
  end

  defp plan_id(week_start), do: "plan:#{Date.to_iso8601(week_start)}"
  defp grocery_id(week_start), do: "grocery_list:#{Date.to_iso8601(week_start)}"
end
