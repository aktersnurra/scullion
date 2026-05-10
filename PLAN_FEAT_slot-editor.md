# PLAN_FEAT_slot-editor

## Philosophy shift

The current slot modal is a CRUD form ("choose recipe → enter servings → assign meal"). The user is actually thinking *"what are we eating Tuesday?"* The modal should match that mental model: pick a dish, adjust portions, choose behavior. Not admin verbs.

Pairs with — and supersedes the modal section of — `PLAN_FEAT_per-slot-suggest.md`. That plan stays valid for the *backend* suggest API; this plan replaces the *frontend modal* design.

## Target layout

```
Tuesday · Dinner                                          [×]

[ 🔍 Search recipes…                                       ]

Suggested
─────────────
🍣  Salmon bowls
    Uses Monday rice · 20 min

🍛  Chicken curry
    Cheap this week · makes leftovers

🍝  Pasta arrabbiata
    15 min · pantry-only

All recipes
─────────────
(scrollable list, same row format)

────────────────────────────────────────

Portions          [ − ]   4   [ + ]

Leftovers for     [ Wed ]  [ Thu ]  [ Fri ]

No dinner planned                              ◯ off

────────────────────────────────────────

                                          [ Save ]
```

No: assign, skip, mark, remove. Just: pick dinner.

## Header copy

- `Tue Dinner` → `Tuesday · Dinner` (full weekday, dot separator, calmer).
- Close (×) is the only chrome action.

## Recipe picker

Dropdown is gone. Replaced with:

- **Search field** at top, instant filter.
- **Suggested list** (3–5 rows) — populated by `PlanningHandler.suggest_recipes_for_slot/2` returning a ranked list with reasoning.
- **All recipes** list below — sorted alphabetically, scrollable, same row format.
- Each row: small thumb (or food emoji fallback), title, one-line meta (time · portions · contextual hint).
- Selected recipe highlights with `--accent-soft` background + `--accent` border.

### Reasoning hints
The "Uses Monday rice", "Cheap at ICA", "leftover friendly" are derived facts, not free text. Sources we already have:

| Hint | Source |
|---|---|
| `Uses {ingredient} from {day}` | Cross-reference recipe ingredients with previous day's leftovers + assigned recipes |
| `Cheap at {store} this week` | DealsHandler current week's discounts intersected with recipe ingredients |
| `Pantry-only` | All recipe ingredients exist in current pantry inventory |
| `Makes leftovers` | Recipe `base_servings >= 4` and `recipe_type == :meal` |
| `{n} min` | `prep_time_minutes + cook_time_minutes` |
| `Recently cooked` (greyed out) | Last assignment within 14 days |

The LLM is *one* source — fast suggestions can come from rule-based ranking even without an LLM call. LLM is for "I want something different" / regenerate-this-suggestion behavior.

## Portions stepper

Replace number input with `[−] N [+]` segmented control. Touch-friendly, kiosk-safe. Min 1, max 12 (sensible household range; rare exceptions can still type via long-press if we wanted, but skip that for MVP).

## Leftovers as toggleable day chips

Replace "Mark as leftovers" button. After picking a recipe with `base_servings > slot.servings` (i.e. portions to spare), show:

```
Leftovers for     [ Wed ] [ Thu ] [ Fri ]
```

Day chips for the *remaining days in this week, after this slot*. Toggleable. Clicking a chip:
- Assigns this same recipe to that day.
- Marks the *target day* as `leftover: true` (current behavior of `mark_leftover/2`).
- Highlights the chip in `--accent-soft`.

Untoggling a chip removes that day's assignment.

This is the killer interaction — instead of going to Wednesday and saying "this uses leftovers", you say from Tuesday "leftovers go here, here, and here."

## "No dinner planned" toggle

Replace "Skip this meal" destructive button. A subtle toggle row:

```
No dinner planned                              [ off ●——— ]
```

When **on**: clears the slot, marks `skipped: true`, dims the entire modal body (recipe picker greys out, portions stepper hidden), only the toggle remains active. Saving applies a `SkipMeal` event.

When **off**: nothing — proceed with normal flow.

## Remove (delete)

Hidden. Reachable only via:
- Long-press on the row in the planner (mobile)
- Right-click context menu on the row (desktop) — overflow `⋯` icon at end of row also OK
- Inside an "Advanced" details disclosure within the modal as a last resort

Not a primary action. Not red text. Not visible on first glance. The user is not deleting production data, they are changing Tuesday dinner.

## Save button

Single primary CTA. Becomes enabled when a recipe is selected (or "No dinner planned" is toggled on). Closes modal on success. No "Cancel" — × in header is the cancel.

## Backend additions

### New / extended functions

#### `PlanningHandler.suggest_recipes_for_slot(plan_id, slot_key, opts \\ [])` 
Returns `{:ok, [%{recipe: Recipe.t(), reasons: [String.t()], score: integer}]} | {:error, term}`

- Default `:limit 5`, `:include_llm false`.
- Pure: no LLM call by default. Combines:
  - Pantry overlap score (Pantry inventory ∩ recipe ingredients).
  - Deal overlap score (current Deals ∩ recipe ingredients, weighted by discount).
  - Leftover-reuse score (previous day's recipe shares ingredients with this candidate).
  - Recency penalty (within 14 days).
  - Sort by total score desc.
- When `:include_llm true` (or `force_llm: true`), also calls the existing/forthcoming `@llm.suggest_slot_recipe/1` for one extra "creative" suggestion that isn't already in the rule-based top-5; result merged in.
- Reasons are human strings: `"Uses pantry spinach"`, `"Coop chicken discount this week"`, `"Reuses Monday rice"`, `"Pantry-only"`, `"Recently cooked"` (suppression).

#### `PlanningHandler.assign_with_leftovers(plan_id, slot_key, recipe_id, servings, leftover_days)`
- Atomic helper: assigns the meal to `slot_key`, then for each `day` in `leftover_days` calls `assign_recipe` (same recipe, default servings = base / 2 or the slot's portion split) followed by `mark_leftover`.
- Returns `{:ok, [events]}` aggregating all events.
- One PubSub broadcast at the end, not per-step (avoid flicker).

### LLM client (still as planned in `PLAN_FEAT_per-slot-suggest.md`)

`suggest_slot_recipe/1` returns `{:ok, %{recipe_id, reasoning}, usage}`. Used only when the user clicks "Try another" inside the modal. Same SpendGuard `:suggest_recipe` bucket and cooldown.

### Decider / events

No new events strictly required — `RecipeAssigned` + `LeftoverMarked` cover the leftover-chip toggling. Optional: add `source: :manual | :llm | :rule_based` to `RecipeAssigned` for telemetry, but skippable for MVP.

## Frontend (`lib/scullion_web/live/planner_live.ex`)

### State on the modal (`socket.assigns.slot_action`)

```elixir
%{
  slot_key: "tue_dinner",
  search: "",
  suggestions: [%{recipe, reasons, score}, ...],
  selected_recipe_id: nil,
  servings: 4,
  leftover_days: MapSet.new(["wed_dinner"]),
  skipped: false,
  loading_suggestions: false
}
```

### New events

- `handle_event("open_slot", %{"slot_key" => sk}, socket)` — initializes the modal, fires async `Task.start(fn -> suggest_recipes_for_slot(...) end)` so suggestions don't block.
- `handle_event("close_slot", _, socket)` — clears slot_action.
- `handle_event("search_slot_recipes", %{"q" => q}, socket)` — updates `slot_action.search`, filters all-recipes list locally.
- `handle_event("pick_recipe", %{"id" => id}, socket)` — sets `selected_recipe_id`, defaults servings to recipe.base_servings.
- `handle_event("inc_servings", _, socket)` / `("dec_servings", _, socket)` — bounded ±1 between 1..12.
- `handle_event("toggle_leftover_day", %{"day" => d}, socket)` — flips MapSet membership.
- `handle_event("toggle_skipped", _, socket)` — flips `skipped`.
- `handle_event("save_slot", _, socket)` — applies the right combination:
  - If skipped: `skip_meal`.
  - Else: `assign_with_leftovers`.
  - Then `close_slot`.
- `handle_info({:suggestions_loaded, ranked}, socket)` — populates `slot_action.suggestions`, clears loading flag.
- `handle_event("regenerate_suggestion", _, socket)` — calls LLM-backed suggest for one alternative (uses spend bucket).

### Hidden remove

- Add a `⋯` icon button at the end of each planner row → opens a small popover with "Remove meal".
- No remove button visible inside the modal at all (per philosophy).

## Tests

### Backend
- `PlanningHandlerTest`:
  - `suggest_recipes_for_slot/2` returns ranked list when pantry/deals/leftovers exist.
  - Recency penalty drops recently-cooked recipes below threshold.
  - `:include_llm true` calls the LLM client and merges its suggestion into the result.
  - `assign_with_leftovers/5` creates AssignRecipe + LeftoverMarked events for each day, in one PubSub broadcast.
- `LLM clients` (live + test): suggest_slot_recipe returns valid recipe_id from candidate set.

### Frontend
- `PlannerLiveTest`:
  - Opening a slot loads suggestions async; modal renders loading state then list.
  - Picking a recipe + saving fires `RecipeAssigned`.
  - Toggling leftover day chips assigns + marks leftover for that day on save.
  - "No dinner planned" toggle disables recipe picker and saves as `MealSkipped`.
  - Searching filters the all-recipes list.
  - Servings stepper bounded to 1..12.

## Migration / rollout

No DB migration. Behavioural changes only.

The current `slot_action` state and existing handler functions stay reachable for safety, but the modal render is fully rewritten. The "Build grocery list" auto-rebuild from the prior session continues to work since it triggers off `RecipeAssigned` events which are still emitted.

## Out of scope

- LLM-driven suggestions on initial open (rule-based only by default; LLM is opt-in via "Try another").
- Long-press / right-click affordance for the hidden remove — for MVP a simple `⋯` button at the end of each row is fine.
- Undo for skipped/removed meals (event sourcing makes this cheap to add later).
- Per-portion split between today's dinner and leftovers (we'll just halve `base_servings` as default; user adjusts servings stepper).

## Estimated work

- Backend (suggest_recipes_for_slot rule engine + assign_with_leftovers): ~half day.
- Frontend modal redesign: ~half day.
- LLM glue + spend bucket (already planned): ~hour.
- Tests: ~hour.

## File list

- `lib/scullion/handlers/planning_handler.ex` (+ ~80 lines: suggest_recipes_for_slot, assign_with_leftovers)
- `lib/scullion/llm/behaviour.ex` (+ suggest_slot_recipe callback, per per-slot-suggest plan)
- `lib/scullion/llm/openrouter_client.ex` / `test_client.ex` (+ implementation)
- `lib/scullion/spend_guard.ex` (+ `:suggest_recipe` bucket)
- `lib/scullion_web/live/planner_live.ex` (modal rewrite + 9 new events; row gets `⋯` button; remove old slot_action handlers)
- `test/scullion/handlers/planning_handler_test.exs`
- `test/scullion_web/live/planner_live_test.exs`
