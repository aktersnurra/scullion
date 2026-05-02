defmodule ScullionWeb.PrepLive do
  use ScullionWeb, :live_view

  alias Scullion.{Handlers.PrepHandler, Prep}

  def mount(_params, _session, socket) do
    week_start = week_start(Date.utc_today())
    plan_id = "plan:#{Date.to_iso8601(week_start)}"
    guide = Prep.get_guide_for_week(week_start)

    {:ok, assign(socket, week_start: week_start, plan_id: plan_id, guide: guide)}
  end

  def handle_event("generate_guide", _params, socket) do
    %{plan_id: plan_id, week_start: week_start} = socket.assigns

    case PrepHandler.generate_guide(plan_id, week_start) do
      {:ok, guide} ->
        {:noreply, assign(socket, guide: guide)}

      {:error, :budget_exceeded} ->
        {:noreply, put_flash(socket, :error, "Monthly LLM budget reached")}

      {:error, :cooldown} ->
        {:noreply, put_flash(socket, :error, "Please wait a moment before generating again")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Prep guide generation failed")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-lg font-semibold">Prep Guide — Week of <%= Date.to_iso8601(@week_start) %></h1>
        <button phx-click="generate_guide" class="px-3 py-1 bg-indigo-600 text-white rounded text-sm">
          Generate Guide
        </button>
      </div>

      <%= if @guide do %>
        <%= if @guide.prep_session do %>
          <div class="mb-6">
            <h2 class="font-medium mb-2">Sunday Prep</h2>
            <div class="grid grid-cols-2 gap-4 text-sm">
              <div><strong>Proteins:</strong> <%= Enum.join(@guide.prep_session["proteins"] || [], ", ") %></div>
              <div><strong>Bases:</strong> <%= Enum.join(@guide.prep_session["bases"] || [], ", ") %></div>
              <div><strong>Sauces:</strong> <%= Enum.join(@guide.prep_session["sauces"] || [], ", ") %></div>
              <div><strong>Vegetables:</strong> <%= Enum.join(@guide.prep_session["vegetables"] || [], ", ") %></div>
            </div>
          </div>
        <% end %>

        <%= if @guide.timeline do %>
          <div class="mb-6">
            <h2 class="font-medium mb-2">Timeline</h2>
            <ol class="space-y-1 text-sm">
              <%= for step <- @guide.timeline do %>
                <li class="flex gap-2">
                  <span class="text-gray-400 w-6"><%= step["step"] %>.</span>
                  <span><%= step["task"] %></span>
                  <span class="text-gray-400"><%= step["duration_min"] %>m</span>
                </li>
              <% end %>
            </ol>
          </div>
        <% end %>

        <%= if @guide.storage_notes do %>
          <div class="mb-6">
            <h2 class="font-medium mb-2">Storage</h2>
            <p class="text-sm text-gray-700"><%= @guide.storage_notes %></p>
          </div>
        <% end %>
      <% else %>
        <p class="text-gray-400 text-sm">No guide yet — assign recipes in the planner then generate a guide.</p>
      <% end %>
    </div>
    """
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end
end
