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
    <div class="max-w-2xl mx-auto p-6">
      <div class="flex items-center justify-between mb-5">
        <div>
          <h1 class="text-xl font-semibold text-gray-900">Prep Guide</h1>
          <div class="text-sm text-gray-400 mt-0.5">Week of <%= Calendar.strftime(@week_start, "%B %-d") %></div>
        </div>
        <button phx-click="generate_guide" class="px-4 py-2 bg-gray-900 hover:bg-gray-700 text-white rounded-lg text-sm font-medium">
          Generate Guide
        </button>
      </div>

      <%= if @guide do %>
        <%= if @guide.prep_session do %>
          <div class="bg-white rounded-2xl border border-gray-100 p-5 mb-4">
            <h2 class="font-medium text-gray-800 mb-3">Sunday Prep</h2>
            <div class="grid grid-cols-2 gap-3 text-sm">
              <div>
                <div class="text-xs text-gray-400 mb-1">Proteins</div>
                <div class="text-gray-700"><%= Enum.join(@guide.prep_session["proteins"] || [], ", ") %></div>
              </div>
              <div>
                <div class="text-xs text-gray-400 mb-1">Bases</div>
                <div class="text-gray-700"><%= Enum.join(@guide.prep_session["bases"] || [], ", ") %></div>
              </div>
              <div>
                <div class="text-xs text-gray-400 mb-1">Sauces</div>
                <div class="text-gray-700"><%= Enum.join(@guide.prep_session["sauces"] || [], ", ") %></div>
              </div>
              <div>
                <div class="text-xs text-gray-400 mb-1">Vegetables</div>
                <div class="text-gray-700"><%= Enum.join(@guide.prep_session["vegetables"] || [], ", ") %></div>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @guide.timeline do %>
          <div class="bg-white rounded-2xl border border-gray-100 p-5 mb-4">
            <h2 class="font-medium text-gray-800 mb-3">Timeline</h2>
            <ol class="space-y-2">
              <%= for step <- @guide.timeline do %>
                <li class="flex gap-3 text-sm">
                  <span class="text-gray-300 w-5 shrink-0 text-right"><%= step["step"] %>.</span>
                  <span class="flex-1 text-gray-700"><%= step["task"] %></span>
                  <span class="text-gray-400 shrink-0"><%= step["duration_min"] %>m</span>
                </li>
              <% end %>
            </ol>
          </div>
        <% end %>

        <%= if @guide.storage_notes do %>
          <div class="bg-white rounded-2xl border border-gray-100 p-5">
            <h2 class="font-medium text-gray-800 mb-2">Storage</h2>
            <p class="text-sm text-gray-600"><%= @guide.storage_notes %></p>
          </div>
        <% end %>
      <% else %>
        <div class="bg-white rounded-2xl border border-gray-100 p-10 text-center">
          <p class="text-gray-400 text-sm">No guide yet — assign recipes in the planner then generate a guide.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end
end
