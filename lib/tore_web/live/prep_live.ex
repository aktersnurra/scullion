defmodule ToreWeb.PrepLive do
  use ToreWeb, :live_view

  alias Tore.{Handlers.PrepHandler, Handlers.PlanningHandler, Prep}

  def mount(_params, _session, socket) do
    week_start = week_start(Date.utc_today())
    plan_id = "plan:#{Date.to_iso8601(week_start)}"
    guide = Prep.get_guide_for_week(week_start)

    {:ok, assign(socket, week_start: week_start, plan_id: plan_id, guide: guide, tab: "timeline")}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket), do: {:noreply, assign(socket, tab: tab)}

  def handle_event("generate_plan", _params, socket) do
    guidance = Tore.Household.get_preferences() |> Tore.Household.prefs_to_dietary_guidance()
    week_start = socket.assigns.week_start

    Task.start(fn ->
      PlanningHandler.generate_plan(socket.assigns.plan_id, week_start,
        mode: :from_catalog,
        dietary_guidance: guidance
      )
    end)

    {:noreply, put_flash(socket, :info, gettext("Generating plan…"))}
  end

  def handle_event("generate_guide", _params, socket) do
    %{plan_id: plan_id, week_start: week_start} = socket.assigns

    case PrepHandler.generate_guide(plan_id, week_start) do
      {:ok, guide} ->
        {:noreply, assign(socket, guide: guide)}

      {:error, :budget_exceeded} ->
        {:noreply, put_flash(socket, :error, gettext("Monthly LLM budget reached"))}

      {:error, :cooldown} ->
        {:noreply, put_flash(socket, :error, gettext("Please wait a moment before generating again"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Prep guide generation failed"))}
    end
  end

  def render(assigns) do
    tabs = [
      %{id: "timeline", label: gettext("Timeline")},
      %{id: "components", label: gettext("Components")},
      %{id: "notes", label: gettext("Notes")}
    ]

    total_min =
      case assigns.guide && assigns.guide.timeline do
        nil -> 0
        steps -> Enum.reduce(steps, 0, fn s, acc -> acc + (s["duration_min"] || 0) end)
      end

    assigns = assign(assigns, tabs: tabs, total_min: total_min)

    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/prep"}>
    <.page max_width={:md}>
      <.card padded={false}>
        <header class="flex items-center justify-between px-6 pt-6 pb-3">
          <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">{gettext("Prep Guide")}</h1>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="generate_plan"
              title={gettext("Generate week plan")}
              class="size-8 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--muted)] hover:text-[var(--text)] hover:bg-[color:var(--hairline)] transition-colors"
            >
              <.icon name="hero-calendar-days" class="size-5" />
            </button>
            <button
              type="button"
              class="h-9 px-3 inline-flex items-center gap-1.5 rounded-[var(--r-lg)] border border-[color:var(--border)] text-[color:var(--muted)] hover:border-[color:var(--subtle)]"
              style="font-size: var(--t-meta);"
            >
              {Calendar.strftime(@week_start, "%b %-d")} – {Calendar.strftime(Date.add(@week_start, 6), "%b %-d")}
              <.icon name="hero-chevron-down" class="size-3.5" />
            </button>
          </div>
        </header>

        <%= if @guide do %>
          <div class="px-6 pt-3 border-t border-[color:var(--hairline)]">
            <div class="flex items-baseline justify-between pb-4 border-b border-[color:var(--hairline)]">
              <h2 class="font-semibold" style="font-size: var(--t-h2);">{gettext("Sunday Prep Plan")}</h2>
              <span :if={@total_min > 0} class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("%{duration} total", duration: format_duration(@total_min))}</span>
            </div>

            <p class="mt-3 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
              {gettext("Batch prep to make the week easier. Most components keep 3–4 days.")}
            </p>

            <div class="mt-4">
              <.tabs items={@tabs} active={@tab} />
            </div>

            <div class="pt-5 pb-6">
              <%= cond do %>
                <% @tab == "timeline" and @guide.timeline -> %>
                  {timeline_render(assigns)}
                <% @tab == "timeline" -> %>
                  <.empty message={gettext("No timeline yet")} />
                <% @tab == "components" and @guide.prep_session -> %>
                  <div class="space-y-4">
                    <div :for={key <- ["proteins", "bases", "sauces", "vegetables"]}>
                      <h3 class="uppercase tracking-wider text-[color:var(--subtle)] mb-1.5" style="font-size: var(--t-micro); font-weight: 600;">{String.capitalize(key)}</h3>
                      <p class="text-[var(--text)]" style="font-size: var(--t-body);">
                        {Enum.join(@guide.prep_session[key] || [], ", ")}
                      </p>
                    </div>
                  </div>
                <% @tab == "components" -> %>
                  <.empty message={gettext("No components")} />
                <% @tab == "notes" -> %>
                  <p :if={@guide.storage_notes} class="text-[var(--text)]" style="font-size: var(--t-body);">{@guide.storage_notes}</p>
                  <.empty :if={!@guide.storage_notes} message={gettext("No notes")} />
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="px-6 py-14 flex flex-col items-center text-center border-t border-[color:var(--hairline)]">
            <div class="mb-5">
              <.icon name="custom-prep" class="size-24" />
            </div>
            <h3 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h2);">{gettext("No guide yet")}</h3>
            <p class="mt-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
              {gettext("Assign recipes in the planner, then generate your prep guide.")}
            </p>
            <div class="mt-5">
              <.button variant={:primary} size={:lg} phx-click="generate_guide">
                <.icon name="hero-sparkles" class="size-4" /> {gettext("Generate guide")}
              </.button>
            </div>
          </div>
        <% end %>
      </.card>
    </.page>
    </Layouts.app>
    """
  end

  defp timeline_render(assigns) do
    {steps, _} =
      Enum.map_reduce(assigns.guide.timeline, 0, fn step, acc ->
        clock = format_clock_min(acc)
        new_acc = acc + (step["duration_min"] || 0)
        {Map.put(step, :clock, clock), new_acc}
      end)

    assigns = assign(assigns, steps: steps)

    ~H"""
    <ol class="relative pl-7">
      <span class="absolute left-2 top-2 bottom-2 w-px bg-[color:var(--hairline)]"></span>
      <li :for={step <- @steps} class="relative pb-5 last:pb-0">
        <span class="absolute -left-7 top-1 size-4 rounded-full bg-[color:var(--accent)] ring-4 ring-[var(--surface)]"></span>
        <div class="flex items-baseline gap-3">
          <span class="text-[color:var(--muted)] tabular-nums w-12 shrink-0" style="font-size: var(--t-meta);">{step.clock}</span>
          <p class="font-semibold text-[var(--text)]" style="font-size: var(--t-body);">{step["task"]}</p>
        </div>
        <p :if={step["detail"]} class="ml-[60px] mt-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{step["detail"]}</p>
      </li>
    </ol>
    """
  end

  defp format_clock_min(min) do
    h = div(min, 60)
    m = rem(min, 60)
    :io_lib.format("~B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  defp format_duration(min) when min >= 60 do
    h = div(min, 60)
    m = rem(min, 60)
    if m == 0, do: "#{h}h", else: "#{h}h #{m}m"
  end

  defp format_duration(min), do: "#{min}m"


  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end
end
