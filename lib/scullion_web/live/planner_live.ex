defmodule ScullionWeb.PlannerLive do
  use ScullionWeb, :live_view

  alias Scullion.{Recipes, Handlers.PlanningHandler, Handlers.GroceriesHandler}
  alias Phoenix.PubSub

  @days ~w[mon tue wed thu fri sat sun]
  @meals ~w[dinner lunch]

  def mount(_params, _session, socket) do
    week_start = week_start(Date.utc_today())
    plan_id = plan_id(week_start)

    if connected?(socket) do
      PubSub.subscribe(Scullion.PubSub, "plan")
    end

    {:ok, plan_state} = PlanningHandler.load_plan(plan_id)
    recipes = Recipes.list(sort: :alphabetical)

    {:ok,
     assign(socket,
       week_start: week_start,
       plan_id: plan_id,
       plan_state: plan_state,
       recipes: recipes,
       view: :week,
       show_lunch: false,
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
    {:noreply, assign(socket, plan_state: plan_state)}
  end

  def render(assigns) do
    assigns = assign(assigns, days: @days, meals: @meals)

    ~H"""
    <div class="p-4">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <button phx-click="prev_week" class="px-3 py-1 border rounded">&larr;</button>
          <span class="font-semibold">Week of <%= Date.to_iso8601(@week_start) %></span>
          <button phx-click="next_week" class="px-3 py-1 border rounded">&rarr;</button>
        </div>
        <div class="flex gap-2">
          <button phx-click="toggle_lunch" class="px-3 py-1 border rounded text-sm">
            <%= if @show_lunch, do: "Hide Lunch", else: "Show Lunch" %>
          </button>
          <button
            phx-click="build_grocery_list"
            class="px-3 py-1 bg-green-600 text-white rounded text-sm"
          >
            Build Grocery List
          </button>
          <button
            phx-click="generate_plan"
            class="px-3 py-1 bg-indigo-600 text-white rounded text-sm"
          >
            Generate Plan
          </button>
        </div>
      </div>

      <div class="grid grid-cols-7 gap-2">
        <%= for day <- @days do %>
          <div class="flex flex-col gap-2">
            <div class="text-center text-xs font-semibold uppercase text-gray-500 py-1">
              <%= String.upcase(day) %>
            </div>
            <.meal_slot
              slot_key={"#{day}_dinner"}
              meal="dinner"
              plan_state={@plan_state}
              recipes={@recipes}
              slot_action={@slot_action}
            />
            <%= if @show_lunch do %>
              <.meal_slot
                slot_key={"#{day}_lunch"}
                meal="lunch"
                plan_state={@plan_state}
                recipes={@recipes}
                slot_action={@slot_action}
              />
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @slot_action do %>
        <.slot_modal
          slot_action={@slot_action}
          plan_state={@plan_state}
          recipes={@recipes}
        />
      <% end %>
    </div>
    """
  end

  attr :slot_key, :string, required: true
  attr :meal, :string, required: true
  attr :plan_state, :any, required: true
  attr :recipes, :list, required: true
  attr :slot_action, :any, required: true

  defp meal_slot(assigns) do
    assigns =
      assign(assigns,
        slot: Map.get(assigns.plan_state.slots, assigns.slot_key),
        pinned: Map.has_key?(assigns.plan_state.pins, assigns.slot_key)
      )

    ~H"""
    <div
      class={[
        "border rounded p-2 min-h-16 cursor-pointer text-sm",
        @slot && @slot.skipped && "opacity-50 line-through",
        @slot && @slot.leftover && "bg-yellow-50"
      ]}
      phx-click="slot_action"
      phx-value-slot_key={@slot_key}
      phx-value-action="menu"
    >
      <div class="text-xs text-gray-400 mb-1"><%= @meal %></div>
      <%= if @slot do %>
        <div class="font-medium truncate"><%= recipe_title(@recipes, @slot.recipe_id) %></div>
        <div class="text-xs text-gray-500 mt-1 flex gap-1">
          <%= if @slot.servings, do: "×#{@slot.servings}" %>
          <%= if @pinned, do: "📌" %>
          <%= if @slot.skipped, do: "✗" %>
          <%= if @slot.leftover, do: "↩" %>
        </div>
      <% else %>
        <div class="text-gray-300 text-xs">—</div>
      <% end %>
    </div>
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
    <div class="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg shadow-lg p-6 w-96 max-h-[80vh] overflow-y-auto">
        <div class="flex justify-between items-center mb-4">
          <h2 class="font-semibold"><%= @slot_action.slot_key %></h2>
          <button phx-click="close_slot_action" class="text-gray-400 hover:text-gray-600">✕</button>
        </div>

        <%= if @slot do %>
          <div class="mb-4 p-3 bg-gray-50 rounded">
            <div class="font-medium"><%= recipe_title(@recipes, @slot.recipe_id) %></div>
            <div class="text-sm text-gray-500">Servings: <%= @slot.servings || "—" %></div>
          </div>
          <div class="flex flex-col gap-2">
            <button
              phx-click="skip_meal"
              phx-value-slot_key={@slot_action.slot_key}
              class="w-full py-2 border rounded text-sm text-left px-3"
            >
              Mark as skipped
            </button>
            <button
              phx-click="mark_leftover"
              phx-value-slot_key={@slot_action.slot_key}
              class="w-full py-2 border rounded text-sm text-left px-3"
            >
              Mark as leftover
            </button>
            <button
              phx-click="remove_recipe"
              phx-value-slot_key={@slot_action.slot_key}
              class="w-full py-2 border rounded text-sm text-left px-3 text-red-600"
            >
              Remove recipe
            </button>
          </div>
          <div class="mt-4 border-t pt-4">
            <div class="text-sm font-medium mb-2">Swap recipe</div>
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
      <select name="recipe_id" class="border rounded px-2 py-1 text-sm w-full">
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
        class="border rounded px-2 py-1 text-sm w-full"
      />
      <button type="submit" class="bg-blue-600 text-white rounded py-2 text-sm">
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

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp plan_id(week_start), do: "plan:#{Date.to_iso8601(week_start)}"
  defp grocery_id(week_start), do: "grocery_list:#{Date.to_iso8601(week_start)}"
end
