# PLAN_FEAT_per-slot-suggest

## Goal

Replace whole-week regenerate with a per-slot "suggest me a recipe for this day" action. User taps a day → slot modal opens → "✨ Suggest a recipe" runs the LLM for *that one slot* using the rest of the week as context. The suggestion previews; user accepts or dismisses.

## Backend

### New handler function (`lib/scullion/handlers/planning_handler.ex`)

```elixir
def suggest_recipe_for_slot(plan_id, slot_key) :: {:ok, suggestion_map} | {:error, term}
```

- Loads plan state via `EventStore.load(plan_id, Decider)`.
- Checks `SpendGuard.allow?(:suggest_recipe)` — new spend bucket, smaller cap than full plan generation.
- Builds context: other days' assigned recipes, week_start, slot_key, pantry snapshot, recent recipe history (avoid recently-cooked).
- Calls `@llm.suggest_slot_recipe(context)` → returns `{:ok, %{recipe_id, servings, reasoning}, usage}`.
- Logs usage with `SpendGuard.log_usage/2`.
- **Does not append an event** — returns the suggestion to the caller, who decides whether to accept.
- On accept, the existing `assign_recipe/4` is called (which fires `RecipeAssigned`).

### LLM client interface (`lib/scullion/llm/`)

- Add `suggest_slot_recipe(context)` callback to the LLM behaviour.
- Implement in the live OpenRouter client; fake in test client.
- Prompt: structured JSON output — `{recipe_id: int, servings: int, reasoning: string}`. Constrain candidates to existing `Recipes.list()` ids to avoid hallucinated recipes.

### Optional: track suggestion provenance

If we want telemetry on manual vs LLM-picked slots:

- Extend `Events.RecipeAssigned` with `source: :manual | :llm` (default `:manual`).
- Update `Decider.evolve/2` to write `source` onto the slot.
- Reflect `source` on the slot map so UI can show a small "✨ suggested" badge.

Not required for MVP; the existing event shape stays back-compatible if we skip this.

### Decider

Reusing `Commands.AssignRecipe` — no new command needed. The "suggestion" is ephemeral state held in the LiveView, not in the event stream.

## Frontend (`lib/scullion_web/live/planner_live.ex`)

### Drop existing whole-week regenerate

- Remove `handle_event("generate_plan", ...)`.
- (Already removed from header UI in earlier pass.)

### New events

- `handle_event("suggest_for_slot", %{"slot_key" => sk}, socket)` — calls `PlanningHandler.suggest_recipe_for_slot/2`. On success, store the suggestion in `socket.assigns.slot_action.suggestion`. On `{:error, :budget_exceeded}` / `:cooldown` / generic — flash error.
- `handle_event("accept_suggestion", _, socket)` — pulls the stored suggestion, calls `assign_recipe`, clears modal.
- `handle_event("discard_suggestion", _, socket)` — clears just the suggestion preview, leaves modal open.

### Slot modal additions

- New "✨ Suggest a recipe" secondary button alongside the existing actions (above the Assign form).
- When `slot_action.suggestion != nil`, show a preview block: recipe title, servings, the LLM's one-line reasoning, plus `[Use this]` / `[Try another]` / `[Dismiss]` buttons.
- Loading state: button shows spinner + disabled while waiting.

## Spend control (`lib/scullion/spend_guard.ex`)

- New bucket `:suggest_recipe` with a cap (e.g. 30 calls/day) — much smaller and cheaper than `:generate_plan` since it's one slot, not seven.
- Cooldown of a few seconds to prevent spam.

## Tests

- `PlanningHandlerTest`:
  - `suggest_recipe_for_slot/2` returns `{:ok, suggestion}` with mocked LLM.
  - Returns `{:error, :budget_exceeded}` when SpendGuard blocks.
  - Returns `{:error, :cooldown}` when called twice in quick succession.
- `PlannerLiveTest`:
  - Clicking "Suggest a recipe" in the modal calls the handler.
  - "Use this" assigns the recipe (verifies `RecipeAssigned` event appended).
  - "Dismiss" clears the suggestion without mutating plan state.
- LLM prompt golden test: suggested `recipe_id` must be in the candidate list, JSON parses, no hallucinated fields.

## Migration

No DB migration required for MVP. Add a `source` column to events only if we adopt telemetry tracking — otherwise the event payload shape is unchanged.

## Out of scope

- Bulk "regenerate the whole week" — gone, replaced entirely by per-slot.
- Showing why the LLM picked it on the row itself (reasoning only visible in the modal preview).
- Multi-suggestion ranking ("show me 3 options") — start with one suggestion + "Try another" re-runs.

## Estimated work

- Backend: ~half a day (handler + LLM call + spend bucket + tests).
- Frontend: ~hour (modal additions + 3 events).
- LLM prompt iteration: open-ended.

## File list

- `lib/scullion/handlers/planning_handler.ex` (+~30 lines)
- `lib/scullion/llm/behaviour.ex` (+1 callback)
- `lib/scullion/llm/openrouter_client.ex` (+ implementation)
- `lib/scullion/llm/test_client.ex` (+ stub)
- `lib/scullion/spend_guard.ex` (+ new bucket)
- `lib/scullion_web/live/planner_live.ex` (+ 3 events, modal additions, drop `generate_plan` event)
- `test/scullion/handlers/planning_handler_test.exs`
- `test/scullion_web/live/planner_live_test.exs`
