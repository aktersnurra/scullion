defmodule ScullionWeb.PlannerLive do
  use ScullionWeb, :live_view

  alias Scullion.{Recipes, Handlers.PlanningHandler, Handlers.GroceriesHandler}
  alias Phoenix.PubSub

  @days ~w[mon tue wed thu fri sat sun]
  @meals ~w[dinner lunch]

  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = week_start(today)
    plan_id = plan_id(week_start)
    list_id = grocery_id(week_start)

    if connected?(socket) do
      PubSub.subscribe(Scullion.PubSub, "plan")
      PubSub.subscribe(Scullion.PubSub, "grocery_list")
    end

    {:ok, plan_state} = PlanningHandler.load_plan(plan_id)
    {:ok, grocery_state} = GroceriesHandler.load_list(list_id)
    recipes = Recipes.list(sort: :alphabetical)

    {:ok,
     assign(socket,
       today: today,
       week_start: week_start,
       plan_id: plan_id,
       list_id: list_id,
       plan_state: plan_state,
       grocery_state: grocery_state,
       recipes: recipes,
       view: :today,
       show_lunch: false,
       slot_action: nil
     )}
  end

  def handle_event("switch_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, view: String.to_existing_atom(view))}
  end

  def handle_event("check_item", %{"item_id" => id}, socket) do
    GroceriesHandler.check_item(socket.assigns.list_id, id, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("uncheck_item", %{"item_id" => id}, socket) do
    GroceriesHandler.uncheck_item(socket.assigns.list_id, id, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("add_grocery_item", %{"name" => name}, socket) do
    GroceriesHandler.add_item(socket.assigns.list_id, name, nil, nil, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("prev_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, -7)
    {:noreply, load_week(socket, week_start)}
  end

  def handle_event("next_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, 7)
    {:noreply, load_week(socket, week_start)}
  end

  def handle_event("toggle_lunch", _params, socket) do
    {:noreply, update(socket, :show_lunch, &(!&1))}
  end

  def handle_event("slot_action", %{"slot_key" => sk, "action" => action}, socket) do
    {:noreply, assign(socket, slot_action: %{slot_key: sk, action: action})}
  end

  def handle_event("close_slot_action", _params, socket) do
    {:noreply, assign(socket, slot_action: nil)}
  end

  def handle_event("assign_recipe", %{"slot_key" => sk, "recipe_id" => rid, "servings" => sv}, socket) do
    recipe_id = String.to_integer(rid)
    servings = String.to_integer(sv)
    PlanningHandler.assign_recipe(socket.assigns.plan_id, sk, recipe_id, servings)
    {:noreply, assign(socket, slot_action: nil)}
  end

  def handle_event("remove_recipe", %{"slot_key" => sk}, socket) do
    PlanningHandler.remove_recipe(socket.assigns.plan_id, sk)
    {:noreply, assign(socket, slot_action: nil)}
  end

  def handle_event("set_servings", %{"slot_key" => sk, "servings" => sv}, socket) do
    PlanningHandler.set_servings(socket.assigns.plan_id, sk, String.to_integer(sv))
    {:noreply, socket}
  end

  def handle_event("skip_meal", %{"slot_key" => sk}, socket) do
    PlanningHandler.skip_meal(socket.assigns.plan_id, sk)
    {:noreply, assign(socket, slot_action: nil)}
  end

  def handle_event("mark_leftover", %{"slot_key" => sk}, socket) do
    PlanningHandler.mark_leftover(socket.assigns.plan_id, sk)
    {:noreply, assign(socket, slot_action: nil)}
  end

  def handle_event("pin_slot", %{"slot_key" => sk, "recipe_id" => rid}, socket) do
    pin = %{type: :recipe, recipe_id: String.to_integer(rid)}
    PlanningHandler.pin_slot(socket.assigns.plan_id, sk, pin)
    {:noreply, assign(socket, slot_action: nil)}
  end

  def handle_event("unpin_slot", %{"slot_key" => sk}, socket) do
    PlanningHandler.unpin_slot(socket.assigns.plan_id, sk)
    {:noreply, socket}
  end

  def handle_event("generate_plan", _params, socket) do
    %{plan_id: plan_id, week_start: week_start} = socket.assigns

    case PlanningHandler.generate_plan(plan_id, week_start) do
      {:ok, _events} -> {:noreply, socket}
      {:error, :budget_exceeded} -> {:noreply, put_flash(socket, :error, "Monthly LLM budget reached")}
      {:error, :cooldown} -> {:noreply, put_flash(socket, :error, "Please wait a moment before generating again")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Plan generation failed")}
    end
  end

  def handle_event("build_grocery_list", _params, socket) do
    %{plan_state: plan_state, week_start: week_start} = socket.assigns
    list_id = grocery_id(week_start)

    recipe_ids =
      plan_state.slots
      |> Map.values()
      |> Enum.map(& &1.recipe_id)
      |> Enum.reject(&is_nil/1)

    GroceriesHandler.build_list(list_id, week_start, recipe_ids)
    {:noreply, socket}
  end

  def handle_info({:events, _events}, socket) do
    {:ok, plan_state} = PlanningHandler.load_plan(socket.assigns.plan_id)
    {:ok, grocery_state} = GroceriesHandler.load_list(socket.assigns.list_id)
    {:noreply, assign(socket, plan_state: plan_state, grocery_state: grocery_state)}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        days: @days,
        meals: @meals,
        week_end: Date.add(assigns.week_start, 6),
        today_day: today_day_key(assigns.today, assigns.week_start),
        today_slot: today_dinner_slot(assigns.plan_state, assigns.today, assigns.week_start),
        grocery_items: sorted_grocery_items(assigns.grocery_state.items)
      )

    ~H"""
    <div>
      <%= if @view == :today do %>
        <.today_view
          today={@today}
          today_slot={@today_slot}
          recipes={@recipes}
          grocery_items={@grocery_items}
          plan_state={@plan_state}
          week_start={@week_start}
        />
      <% else %>
        <.week_view
          week_start={@week_start}
          week_end={@week_end}
          days={@days}
          today={@today}
          plan_state={@plan_state}
          recipes={@recipes}
          slot_action={@slot_action}
          show_lunch={@show_lunch}
        />
        <%= if @slot_action do %>
          <.slot_modal slot_action={@slot_action} plan_state={@plan_state} recipes={@recipes} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :today, :any, required: true
  attr :today_slot, :any, required: true
  attr :recipes, :list, required: true
  attr :grocery_items, :list, required: true
  attr :plan_state, :any, required: true
  attr :week_start, :any, required: true

  defp today_view(assigns) do
    recipe = recipe_by_id(assigns.recipes, assigns.today_slot[:recipe_id])
    assigns = assign(assigns, recipe: recipe)

    ~H"""
    <div class="min-h-[calc(100vh-3.5rem)] flex items-center justify-center p-6">
      <div class="flex gap-6 w-full max-w-3xl">
        <%!-- Today card --%>
        <div class="flex-1 bg-white rounded-3xl border border-gray-100 overflow-hidden shadow-sm">
          <%!-- Top bar with calendar nav --%>
          <div class="flex items-center justify-between px-5 pt-5 pb-0">
            <button phx-click="switch_view" phx-value-view="week"
                    class="w-8 h-8 flex items-center justify-center rounded-xl hover:bg-gray-100 text-gray-400"
                    title="Week view">
              <.icon name="hero-calendar-days" class="w-5 h-5" />
            </button>
            <div class="text-xs font-semibold uppercase tracking-widest text-gray-400">
              <%= Calendar.strftime(@today, "%A, %B %-d") %>
            </div>
            <div class="w-8" />
          </div>

          <div class="p-6 pt-4 pb-4">
            <%= if @recipe do %>
              <h1 class="text-3xl font-bold text-gray-900 mb-4 leading-tight"><%= @recipe.title %></h1>
              <div class="space-y-2 mb-2">
                <%= if @today_slot[:servings] do %>
                  <div class="flex items-center gap-2 text-sm text-gray-500">
                    <.icon name="hero-user-group" class="w-4 h-4" />
                    <span><%= @today_slot[:servings] %> servings</span>
                  </div>
                <% end %>
                <%= if @today_slot[:leftover] do %>
                  <div class="flex items-center gap-2 text-sm text-gray-500">
                    <.icon name="hero-arrow-path" class="w-4 h-4" />
                    <span>Leftovers tomorrow</span>
                  </div>
                <% end %>
              </div>
            <% else %>
              <h1 class="text-2xl font-bold text-gray-300 mb-4">No dinner planned</h1>
            <% end %>
          </div>

          <%= if @recipe && @recipe.image_path do %>
            <img src={@recipe.image_path} class="w-full h-52 object-cover" />
          <% else %>
            <div class="w-full h-52 bg-gray-50 flex items-center justify-center">
              <.icon name="hero-fire" class="w-12 h-12 text-gray-200" />
            </div>
          <% end %>

          <div class="p-6 pt-4">
            <%= if @recipe && @recipe.source_url do %>
              <a href={@recipe.source_url} target="_blank"
                 class="w-full flex items-center justify-center gap-2 bg-green-600 hover:bg-green-700 text-white rounded-2xl py-3.5 font-semibold text-sm transition-colors">
                <.icon name="hero-fire" class="w-4 h-4" /> Start cooking
              </a>
            <% else %>
              <button class="w-full flex items-center justify-center gap-2 bg-green-600 hover:bg-green-700 text-white rounded-2xl py-3.5 font-semibold text-sm">
                <.icon name="hero-fire" class="w-4 h-4" /> Start cooking
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Grocery list panel --%>
        <div class="w-64 bg-white rounded-3xl border border-gray-100 shadow-sm flex flex-col overflow-hidden">
          <div class="p-5 pb-3 flex items-center justify-between">
            <h2 class="font-semibold text-gray-900">Grocery list</h2>
            <%= if Enum.any?(@grocery_items, & !&1.checked) do %>
              <span class="bg-gray-900 text-white text-xs font-semibold rounded-full w-6 h-6 flex items-center justify-center">
                <%= Enum.count(@grocery_items, & !&1.checked) %>
              </span>
            <% end %>
          </div>

          <div class="flex-1 overflow-y-auto px-3 pb-2">
            <%= if @grocery_items == [] do %>
              <p class="text-xs text-gray-400 text-center py-6">No items yet</p>
            <% else %>
              <ul class="space-y-0.5">
                <%= for item <- @grocery_items do %>
                  <li class="flex items-center gap-3 px-2 py-2 rounded-xl hover:bg-gray-50">
                    <button
                      phx-click={if item.checked, do: "uncheck_item", else: "check_item"}
                      phx-value-item_id={item.id}
                      class="shrink-0"
                    >
                      <div class={[
                        "w-5 h-5 rounded border-2 flex items-center justify-center transition-colors",
                        item.checked && "bg-green-500 border-green-500",
                        !item.checked && "border-gray-300"
                      ]}>
                        <%= if item.checked do %>
                          <.icon name="hero-check" class="w-3 h-3 text-white" />
                        <% end %>
                      </div>
                    </button>
                    <span class={["flex-1 text-sm", item.checked && "line-through text-gray-400", !item.checked && "text-gray-700"]}>
                      <%= item.name %>
                    </span>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div class="px-3 pb-4 pt-2 border-t border-gray-50">
            <form phx-submit="add_grocery_item" class="flex items-center gap-2">
              <input type="text" name="name" placeholder="Add item" required
                     class="flex-1 text-sm text-gray-700 placeholder-gray-400 border-0 focus:outline-none bg-transparent py-2" />
              <button type="submit" class="text-gray-400 hover:text-gray-600">
                <.icon name="hero-plus" class="w-4 h-4" />
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :week_start, :any, required: true
  attr :week_end, :any, required: true
  attr :days, :list, required: true
  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true
  attr :slot_action, :any, required: true
  attr :show_lunch, :boolean, required: true
  attr :today, :any, required: true

  defp week_view(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-5">
        <div class="flex items-center gap-2">
          <button phx-click="switch_view" phx-value-view="today"
                  class="w-8 h-8 flex items-center justify-center rounded-xl hover:bg-gray-100 text-gray-400"
                  title="Back to today">
            <.icon name="hero-calendar-days" class="w-5 h-5" />
          </button>
          <button phx-click="prev_week"
                  class="w-8 h-8 flex items-center justify-center rounded-xl hover:bg-gray-100 text-gray-400">
            <.icon name="hero-chevron-left" class="w-4 h-4" />
          </button>
          <div class="text-center">
            <div class="font-semibold text-gray-900">This week</div>
            <div class="text-xs text-gray-400">
              <%= Calendar.strftime(@week_start, "%b %-d") %> – <%= Calendar.strftime(@week_end, "%b %-d, %Y") %>
            </div>
          </div>
          <button phx-click="next_week"
                  class="w-8 h-8 flex items-center justify-center rounded-xl hover:bg-gray-100 text-gray-400">
            <.icon name="hero-chevron-right" class="w-4 h-4" />
          </button>
        </div>
        <div class="flex items-center gap-2">
          <button phx-click="build_grocery_list"
                  class="px-3 py-1.5 text-sm border border-gray-200 rounded-lg text-gray-600 hover:bg-gray-50">
            Build grocery list
          </button>
          <button phx-click="generate_plan"
                  class="flex items-center gap-1.5 px-4 py-2 text-sm bg-green-600 hover:bg-green-700 text-white rounded-xl font-medium">
            <.icon name="hero-sparkles" class="w-4 h-4" /> Generate plan
          </button>
        </div>
      </div>

      <%!-- Week dots --%>
      <div class="flex justify-center gap-2 mb-5">
        <%= for {day, i} <- Enum.with_index(@days) do %>
          <% date = Date.add(@week_start, i) %>
          <% is_today = date == @today %>
          <% has_recipe = Map.get(@plan_state.slots, "#{day}_dinner") |> then(& &1 && &1.recipe_id) %>
          <div class={[
            "w-2 h-2 rounded-full transition-colors",
            is_today && "bg-green-500",
            !is_today && has_recipe && "bg-gray-400",
            !is_today && !has_recipe && "bg-gray-200"
          ]} title={Calendar.strftime(date, "%A")} />
        <% end %>
      </div>

      <%!-- Day list --%>
      <div class="bg-white rounded-2xl border border-gray-100 overflow-hidden divide-y divide-gray-50">
        <%= for {day, i} <- Enum.with_index(@days) do %>
          <% date = Date.add(@week_start, i) %>
          <% is_today = date == @today %>
          <.week_row
            day={day}
            date={date}
            is_today={is_today}
            slot_key={"#{day}_dinner"}
            meal="Dinner"
            plan_state={@plan_state}
            recipes={@recipes}
            slot_action={@slot_action}
          />
          <%= if @show_lunch do %>
            <.week_row
              day={day}
              date={date}
              is_today={false}
              slot_key={"#{day}_lunch"}
              meal="Lunch"
              plan_state={@plan_state}
              recipes={@recipes}
              slot_action={@slot_action}
            />
          <% end %>
        <% end %>
      </div>

      <%!-- Footer --%>
      <div class="mt-4 flex items-center justify-between text-xs text-gray-400 px-1">
        <button phx-click="toggle_lunch" class="hover:text-gray-600">
          <%= if @show_lunch, do: "Hide lunch", else: "Show lunch" %>
        </button>
        <.plan_summary plan_state={@plan_state} recipes={@recipes} />
      </div>
    </div>
    """
  end

  attr :day, :string, required: true
  attr :date, :any, required: true
  attr :is_today, :boolean, required: true
  attr :slot_key, :string, required: true
  attr :meal, :string, required: true
  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true
  attr :slot_action, :any, required: true

  defp week_row(assigns) do
    slot = Map.get(assigns.plan_state.slots, assigns.slot_key)
    recipe = recipe_by_id(assigns.recipes, slot[:recipe_id])
    leftover_days = leftover_label(assigns.plan_state, assigns.slot_key, assigns.day)
    assigns = assign(assigns, slot: slot, recipe: recipe, leftover_days: leftover_days)

    ~H"""
    <div
      class={[
        "flex items-center gap-4 px-4 py-3 cursor-pointer hover:bg-gray-50 transition-colors",
        @slot && @slot.skipped && "opacity-40"
      ]}
      phx-click="slot_action"
      phx-value-slot_key={@slot_key}
      phx-value-action="menu"
    >
      <%!-- Day label --%>
      <div class="w-12 shrink-0">
        <div class={["text-xs font-medium uppercase tracking-wide", @is_today && "text-green-600", !@is_today && "text-gray-400"]}>
          <%= String.upcase(@day) %>
        </div>
        <div class={["text-xl font-bold leading-tight", @is_today && "text-green-600", !@is_today && "text-gray-800"]}>
          <%= Calendar.strftime(@date, "%-d") %>
        </div>
        <%= if @is_today do %>
          <div class="text-xs text-green-500 font-medium">Today</div>
        <% end %>
      </div>

      <%!-- Thumbnail --%>
      <%= if @recipe && @recipe.image_path do %>
        <img src={@recipe.image_path} class="w-16 h-16 rounded-xl object-cover shrink-0" />
      <% else %>
        <div class={[
          "w-16 h-16 rounded-xl shrink-0 flex items-center justify-center",
          @slot && "bg-gray-100",
          !@slot && "bg-gray-50 border-2 border-dashed border-gray-200"
        ]}>
          <%= cond do %>
            <% @slot && @slot.leftover -> %>
              <.icon name="hero-arrow-path" class="w-5 h-5 text-amber-400" />
            <% @slot && @slot.skipped -> %>
              <.icon name="hero-x-mark" class="w-5 h-5 text-gray-400" />
            <% @slot -> %>
              <.icon name="hero-fire" class="w-5 h-5 text-gray-300" />
            <% true -> %>
              <.icon name="hero-plus" class="w-5 h-5 text-gray-300" />
          <% end %>
        </div>
      <% end %>

      <%!-- Recipe info --%>
      <div class="flex-1 min-w-0">
        <%= if @recipe do %>
          <div class="font-semibold text-gray-900 truncate"><%= @recipe.title %></div>
          <div class="flex items-center gap-3 mt-1 text-xs text-gray-400">
            <%= if @slot.servings do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-user-group" class="w-3 h-3" /> <%= @slot.servings %> servings
              </span>
            <% end %>
            <%= if (@recipe.prep_time_minutes || 0) + (@recipe.cook_time_minutes || 0) > 0 do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-clock" class="w-3 h-3" />
                <%= (@recipe.prep_time_minutes || 0) + (@recipe.cook_time_minutes || 0) %> min
              </span>
            <% end %>
            <%= if @slot.leftover do %>
              <span>Uses leftovers</span>
            <% end %>
          </div>
        <% else %>
          <div class="text-sm text-gray-400">
            <%= if @slot && @slot.skipped, do: "Skipped", else: "Tap to add" %>
          </div>
        <% end %>
      </div>

      <%!-- Leftover pill --%>
      <%= if @leftover_days do %>
        <div class="shrink-0 flex items-center gap-1.5 bg-gray-50 border border-gray-200 rounded-full px-3 py-1.5 text-xs text-gray-500">
          <.icon name="hero-arrow-path" class="w-3 h-3" />
          <span>Leftovers for<br /><span class="font-medium"><%= @leftover_days %></span></span>
        </div>
      <% end %>

      <%!-- Chevron --%>
      <.icon name="hero-chevron-right" class="w-4 h-4 text-gray-300 shrink-0" />
    </div>
    """
  end

  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true

  defp plan_summary(assigns) do
    filled = assigns.plan_state.slots |> Map.values() |> Enum.count(& &1.recipe_id)
    total_servings =
      assigns.plan_state.slots
      |> Map.values()
      |> Enum.reduce(0, fn s, acc -> acc + (s.servings || 0) end)
    assigns = assign(assigns, filled: filled, total_servings: total_servings)

    ~H"""
    <span>
      <%= @filled %> meals · <%= @total_servings %> portions
    </span>
    """
  end

  attr :slot_action, :map, required: true
  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true

  defp slot_modal(assigns) do
    assigns =
      assign(assigns,
        slot: Map.get(assigns.plan_state.slots, assigns.slot_action.slot_key),
        pinned: Map.has_key?(assigns.plan_state.pins, assigns.slot_action.slot_key)
      )

    ~H"""
    <div class="fixed inset-0 bg-black/40 flex items-center justify-center z-50" phx-click="close_slot_action">
      <div class="bg-white rounded-2xl shadow-xl p-6 w-96 max-h-[80vh] overflow-y-auto" phx-click-stop="true">
        <div class="flex justify-between items-center mb-4">
          <h2 class="font-semibold text-gray-800"><%= slot_label(@slot_action.slot_key) %></h2>
          <button phx-click="close_slot_action" class="text-gray-400 hover:text-gray-600 text-lg leading-none">✕</button>
        </div>

        <%= if @slot do %>
          <div class="mb-4 p-3 bg-gray-50 rounded-lg">
            <div class="font-medium text-gray-800"><%= recipe_title(@recipes, @slot.recipe_id) %></div>
            <div class="text-sm text-gray-400 mt-0.5">Servings: <%= @slot.servings || "—" %></div>
          </div>
          <div class="flex flex-col gap-1.5 mb-4">
            <button phx-click="skip_meal" phx-value-slot_key={@slot_action.slot_key}
                    class="w-full py-2 px-3 border border-gray-200 rounded-lg text-sm text-left hover:bg-gray-50">
              Mark as skipped
            </button>
            <button phx-click="mark_leftover" phx-value-slot_key={@slot_action.slot_key}
                    class="w-full py-2 px-3 border border-gray-200 rounded-lg text-sm text-left hover:bg-gray-50">
              Mark as leftover
            </button>
            <button phx-click="remove_recipe" phx-value-slot_key={@slot_action.slot_key}
                    class="w-full py-2 px-3 border border-red-100 rounded-lg text-sm text-left text-red-500 hover:bg-red-50">
              Remove recipe
            </button>
          </div>
          <div class="border-t border-gray-100 pt-4">
            <div class="text-sm font-medium text-gray-600 mb-2">Swap recipe</div>
            <.recipe_picker slot_key={@slot_action.slot_key} recipes={@recipes} />
          </div>
        <% else %>
          <.recipe_picker slot_key={@slot_action.slot_key} recipes={@recipes} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :slot_key, :string, required: true
  attr :recipes, :list, required: true

  defp recipe_picker(assigns) do
    ~H"""
    <form phx-submit="assign_recipe" class="flex flex-col gap-2">
      <input type="hidden" name="slot_key" value={@slot_key} />
      <select name="recipe_id" class="border border-gray-200 rounded-lg px-2 py-2 text-sm w-full bg-white focus:outline-none focus:ring-2 focus:ring-green-500">
        <option value="">Select a recipe…</option>
        <%= for r <- @recipes do %>
          <option value={r.id}><%= r.title %></option>
        <% end %>
      </select>
      <input
        type="number"
        name="servings"
        placeholder="Servings"
        min="1"
        class="border border-gray-200 rounded-lg px-2 py-2 text-sm w-full focus:outline-none focus:ring-2 focus:ring-green-500"
      />
      <button type="submit" class="bg-green-600 hover:bg-green-700 text-white rounded-lg py-2 text-sm font-medium">
        Assign
      </button>
    </form>
    """
  end

  defp load_week(socket, week_start) do
    plan_id = plan_id(week_start)
    {:ok, plan_state} = PlanningHandler.load_plan(plan_id)
    assign(socket, week_start: week_start, plan_id: plan_id, plan_state: plan_state)
  end

  defp recipe_title(recipes, recipe_id) do
    Enum.find_value(recipes, "Unknown", fn r ->
      if r.id == recipe_id, do: r.title
    end)
  end

  defp recipe_by_id(_recipes, nil), do: nil
  defp recipe_by_id(recipes, id), do: Enum.find(recipes, &(&1.id == id))

  defp slot_label(slot_key) do
    [day, meal] = String.split(slot_key, "_", parts: 2)
    "#{String.capitalize(day)} #{String.capitalize(meal)}"
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp leftover_label(plan_state, slot_key, day) do
    [_, meal] = String.split(slot_key, "_", parts: 2)
    slot = Map.get(plan_state.slots, slot_key)
    unless slot && slot.recipe_id do
      nil
    else
      days_after =
        @days
        |> Enum.drop_while(&(&1 != day))
        |> Enum.drop(1)
        |> Enum.filter(fn d ->
          future_slot = Map.get(plan_state.slots, "#{d}_#{meal}")
          future_slot && future_slot.leftover
        end)
        |> Enum.map(&String.capitalize/1)

      if days_after == [], do: nil, else: Enum.join(days_after, ", ")
    end
  end

  defp today_day_key(today, week_start) do
    offset = Date.diff(today, week_start)
    Enum.at(@days, offset)
  end

  defp today_dinner_slot(plan_state, today, week_start) do
    day_key = today_day_key(today, week_start)
    if day_key, do: Map.get(plan_state.slots, "#{day_key}_dinner"), else: nil
  end

  defp sorted_grocery_items(items) do
    items
    |> Map.values()
    |> Enum.sort_by(fn i -> {i.checked, i.name} end)
  end

  defp plan_id(week_start), do: "plan:#{Date.to_iso8601(week_start)}"
  defp grocery_id(week_start), do: "grocery_list:#{Date.to_iso8601(week_start)}"
end
