# Tore — AI-Native Meal Planner & Kitchen Kiosk

> *Tore* is a self-hosted family meal planner. The previous incarnation was *Scullion*,
> a competent but conventional CRUD-shaped planner. This document specifies the
> AI-native rewrite. Where this spec disagrees with the codebase, this spec wins.

## Status

- **Source-of-truth date:** 2026-05-30
- **2026-05-31:** Reversed the Family→Household naming. `Tore.Household` is canonical; `Tore.Family.*` deleted.
- **Supersedes:** the original Scullion SPEC.md (2026-05-02), now archived in git history at commit `af0ad48`.
- **Companion docs:** `LLM-NATIVE-FEATURES.md` (the design brief this spec absorbs), `PLAN.md` (module-by-module breakdown), `PLAN_FEAT_*.md` (per-feature plans).
- **Naming:** the project is *Tore*. Any remaining reference to Scullion or Family in code is legacy and slated for deletion (see §Removed in Rewrite).

---

## Core Philosophy

Two sentences govern every decision in this spec:

1. **The system has a good guess and makes it easy to say yes or make a small correction.** The LLM does the work. The user approves, ignores, or nudges.
2. **The system should be more wrong about your kitchen and more right about your life.** Pantry counts will drift. Receipt scans will be skipped. But the system can learn that you skip Thursdays, that fish on weekdays doesn't stick, and that ICA has pork on sale — and that's the value.

Derived rules:

- **Skipping is first-class and neutral.** One tap. No "why?", no cascade warning. The plan is a proposal, not a contract.
- **No nagging.** No notifications about logging, no streaks, no reminders. The app is ready when you come to it.
- **The grocery list is the reliability anchor.** It works even if everything else is chaos. Manual add always works.
- **The kiosk has one job.** Tonight's meal + what's already prepped. Glanceable in two seconds with floury hands.
- **Trust the user's choices.** When the user overrides a suggestion, the app does not ask why. It notes the event and moves on.
- **Surface, never push.** Proactive intelligence appears in the UI when you open the app. It never sends a notification.

---

## Two Interfaces, One Backend

```
┌──────────────────────┐         ┌──────────────────────────────────┐
│  Raspberry Pi 5      │         │  VPS                              │
│  Nerves kiosk        │         │                                  │
│  Chromium ──────────────HTTPS──▶  Phoenix + LiveView              │
│  Device-token auth   │         │  Ecto + SQLite                    │
└──────────────────────┘         │  OpenRouter (LLM + vision)        │
                                 │  Garage (S3) for images           │
┌──────────────────────┐         │  Quantum scheduler                │
│  Phone / laptop      │         │  EventStore (planning, groceries) │
│  Browser ──────────────HTTPS──▶                                   │
│  16-digit code auth  │         └──────────────────────────────────┘
└──────────────────────┘
```

The Pi is a thin client. All logic runs on the server. The kiosk gets a deliberately
restricted UI (see §Kiosk). The phone/laptop gets the full planner.

---

## Pattern Strategy

Two aggregates are event-sourced via the Decider pattern. Everything else is Ecto CRUD
behind a context boundary. LiveViews call context APIs only; Handlers orchestrate IO.

### Event-sourced

| Aggregate     | Why                                                                |
|---------------|--------------------------------------------------------------------|
| **Planning**  | LLM-orchestrated workflow with frequent user tweaks. Events are the substrate from which insights are synthesised. |
| **Groceries** | Multi-user real-time checklist. Granular events enable PubSub sync and natural undo. |

### CRUD

| Context       | Role                                                              |
|---------------|-------------------------------------------------------------------|
| **Accounts**  | Users, sessions, per-user prefs.                                  |
| **Household** | Shared household-level state (preferences, insights, members). |
| **Recipes**   | Reference catalog.                                                |
| **Deals**     | Scraped weekly, expire automatically.                             |
| **Pantry**    | Approximate inventory. **No primary management UI.** See §Pantry. |
| **Costs**     | Receipts logged for cost tracking. **Not in main nav.**           |
| **Prep**      | LLM-generated text guides. Read-only.                             |
| **CounterNotes** | Ambient suggestions surfaced on Home/Plan/Kiosk. See §Proactive Intelligence. |
| **AIOperations** | Audit log of every LLM call with correlation IDs and token usage. |

---

## The Six LLM-Native Features

These are the features that distinguish Tore from an app-that-calls-an-LLM. Each is
required; none is optional.

### 1. Longitudinal Learning (Family Insights)

A weekly Quantum job (`InsightsHandler.synthesise_weekly`, Sat 06:00) reads the planning
event stream from the last 28 days and asks the LLM to produce a small set of
natural-language observations about how the family actually eats.

**Inputs the LLM must consider:**

- `MealSkipped` events grouped by weekday → "skips Thursdays 7/10 weeks"
- `RecipeRemoved` and `RecipeSwapped` events → infer dislikes and friction
- `LeftoverDay` patterns → which cascades survive, which don't
- Slot fill rate by week → "rarely plans past Wednesday"

**Storage:** `household_insights` table — small (max ~10 active observations per household),
text-typed, with a `dismissed` flag and a `superseded_by` link so the synthesiser can
replace stale insights without losing history.

**Output use:** `SystemPrompt.build/0` injects active insights into every LLM call —
planning, chat, suggestions. The user sees them on the Settings → Kitchen Memory page
and can dismiss any insight that's wrong; dismissed insights are tombstoned, not
deleted, so the synthesiser won't re-create them.

**Hard rule:** There is no rating UI. There is no "how was dinner?" prompt. The
event stream is the only signal.

### 2. Natural-Language Commands on the Planner (Tool-Calling Agent)

The planning Decider already has the right command grammar: `AssignRecipe`, `SwapRecipe`,
`SkipMeal`, `MarkLeftover`, `SetServings`, `PinSlot`, `RemoveRecipe`. The LLM is an
**agent** over these — each Decider command is exposed as a tool, plus a small set of
read-only lookup tools so the LLM can resolve real-world references on its own.

**Flow:**

1. User types into the planner command bar: *"What's quick for Tuesday? Move salmon to Friday."*
2. `PlannerAgent.run/2` opens a tool-calling loop with the LLM. The system prompt carries family preferences, active insights, and the current week state.
3. The LLM may call any of the tools below in any order, possibly several turns deep.
4. Action tools execute through `PlanningHandler` exactly as if the equivalent button had been clicked — same Decider, same events, same PubSub broadcast. Read tools just return data.
5. The loop ends when the LLM emits a final assistant message (or hits the safety limit). The planner re-renders. A confirmation toast lists what was done with an undo button.

**Tool surface (V1):**

| Tool | Kind | Purpose |
|------|------|---------|
| `assign_recipe(slot_key, recipe_id, servings?)` | action | Place a recipe in a slot |
| `swap_recipe(from_slot_key, to_slot_key)` | action | Move a recipe between slots |
| `skip_meal(slot_key)` | action | Mark a slot as skipped |
| `mark_leftover(slot_key, source_slot_key)` | action | Cascade a previous meal forward |
| `set_servings(slot_key, servings)` | action | Adjust servings |
| `remove_recipe(slot_key)` | action | Clear a slot |
| `search_recipes(query?, max_minutes?, tags?, limit?)` | read | Search the catalog |
| `recent_history(weeks?)` | read | What was planned/cooked recently |
| `pantry_snapshot()` | read | Approximate pantry inventory |
| `active_deals()` | read | Current store deals |
| `ask_user(question)` | action | Surface a clarifying question inline and end the turn |

**Loop rules (enforced by `PlannerAgent`):**

- Max 6 LLM round-trips per user utterance. After 6, the agent forces a final summary turn with no tools available.
- Max 12 action-tool calls per utterance (read tools don't count against this).
- Action tools are executed *sequentially* in call order, not in parallel — the Decider must see consistent state between commands.
- If an action tool returns an error (e.g. `:slot_locked`), the error is fed back to the LLM, which decides whether to retry, alter the plan, or call `ask_user`.
- `ask_user` is terminal: the loop ends immediately and the planner shows the question.
- Every loop iteration is logged to `AIOperations` with a shared correlation ID and a per-call `step_index`.

**Required LLM callback:** `chat_with_tools(system :: String.t(), messages :: [map()], tools :: [map()], opts :: keyword()) :: {:ok, response, usage} | {:error, term()}` where `response` is either `{:message, text}` or `{:tool_calls, [%{id, name, args}]}`. See §LLM Interface Conventions.

**Hard rules:**

- Buttons still work. NL is the power path; it is never the only path.
- The LLM cannot read or write anything outside the registered tool surface. No direct DB access from prompts, no template-expanded pantry dumps mid-loop — only what the LLM asks for via a read tool.
- The agent never silently guesses an ambiguous reference. If "the salmon" matches two recipes, the LLM is expected to call `ask_user`. The planner enforces this by not having a "best guess" fallback path.

### 3. Proactive Intelligence (Ambient Scan)

A cheap daily Quantum job (`AmbientScan.run`, every morning at 07:00) inspects the
current week's plan, pantry, deals, and prep state and writes counter notes when it
sees something worth surfacing.

**Required rules:**

| Trigger | Surface | Note kind |
|---------|---------|-----------|
| Pantry item expiring in ≤3 days AND a catalog recipe uses it AND that recipe is not in the current plan | `home`, `plan` | `expiring_match` |
| A cascade plan depends on Sunday prep but Sunday slot is empty/unplanned | `plan` | `cascade_break` |
| It is Wednesday or later AND the current week has ≥3 unplanned dinners | `home`, `plan` | `unplanned_week` |
| A deal matches a high-affinity catalog recipe (frequently chosen, never swapped) | `home` | `deal_match` |

**Output:** Each rule writes a `CounterNote` with `kind`, `body`, `surface`, optional
`recipe_id`/`pantry_item_id` payload, and `expires_at`. Notes are scoped to one of
three surfaces: `home`, `plan`, `kiosk`. Notes auto-expire (end of day for daily, end
of week for weekly).

**Hard rule:** Counter notes appear inline on the relevant surface. They are never
delivered as push, email, or any other interruption. `build_home_note/1`'s current
stub (writes "Ready to cook tonight?" unconditionally) is replaced by this scan.

### 4. Pantry as Inference, not Management

**Demotion in detail:**

- The `/pantry` route is removed from main nav.
- `pantry_live.ex` becomes a read-only "Here's what we think you have" view, reachable from Settings. It supports one action: **remove an item** (the user says "I don't have this"). It does not support add or edit.
- Adding to the pantry happens via three implicit channels:
  - Checked-off grocery items → automatic `Pantry.add_item` (closed loop, see §5)
  - Parsed receipts → automatic `Pantry.add_item` per line item
  - Photo-of-shelf → vision LLM → preview → confirm. This is the only explicit add path, and it lives inside chat, not in a pantry CRUD form.
- The LLM treats pantry as **approximate**. Prompts say things like *"probably has olive oil, last seen 3 weeks ago"*. The pantry context exposes a `last_seen_at` field that the system prompt reads.

**Hard rule:** Spec or implementation work that adds back a primary pantry-management
screen is a regression of this requirement.

### 5. Receipt → Pantry Closed Loop

When a receipt photo is parsed for cost tracking, the same parsed line items must also
be written to the pantry. This is a single user action with two outcomes.

**Required change:** `CostsHandler.parse_and_log_receipt/2` must call
`Pantry.add_item/1` for each line item after logging the receipt. The existing
two-step `confirm_receipt` flow (which already writes to pantry) becomes the explicit
"review and edit" path; auto-write is the default for receipts the user submits via
the chat photo pipeline.

### 6. Fridge Photo → Suggestions

The vision LLM already classifies photos as `:fridge`. The flow must complete:

1. User uploads a fridge photo via chat.
2. `LLM.classify_image/1` → `:fridge`.
3. `LLM.identify_fridge_contents/1` → list of likely ingredients.
4. `Recipes.suggest_from_ingredients/1` matches against the catalog, ranked by ingredient overlap and by family-insight affinity.
5. Chat replies with 3 specific recipe suggestions, each with an "add to tonight" button.

Today the chat replies *"Want me to suggest some recipes?"* and stops. That is the
gap.

---

## Interfaces

### Kiosk (`/kiosk`)

The kiosk is intentionally narrow.

**Primary surface:**
- Tonight's recipe card: name, image, servings, total time, "Start cooking" button (→ `/kiosk/cooking/:id`).
- Components already prepped (cross-referenced with `prep` state).
- One-line counter note if any is active for surface `kiosk`.

**Secondary:**
- A horizontal strip showing the next 3 days' planned meals. No interaction beyond "look at it."
- A button to open Kiosk Chat — a deliberately restricted chat that only answers cooking/recipe questions (not planning, not pantry edits).

**Hard rules:**
- No week calendar on the kiosk root.
- No plan editing on the kiosk. Planning happens on phone/laptop.
- No "report back" UI on the prep guide. The prep guide is a document you read.

### Home (`/`)

The phone/laptop landing surface, distinct from the planner.

- Tonight + tomorrow card pair.
- Active counter notes for surface `home`.
- A week strip showing this week's plan at a glance.
- FAB → `/chat`.

### Planner (`/plan`)

- Week view with editable slots.
- Counter notes for surface `plan` at the top.
- A command bar at the bottom: text input + voice (phase ≥ 8) that runs through `PlannerAgent` (§2).
- Slot interactions still work via tap (assign, swap, skip, mark leftover, set servings).

### Chat (`/chat`)

Full-screen chat that accepts text and photos. Photos are classified
(`receipt | recipe | pantry_items | fridge | unknown`) and routed to the appropriate
review or suggestion flow. Each conversation has a system prompt built from family
preferences, family insights, current week context, and approximate pantry state.

### Groceries (`/groceries`)

The reliability anchor. Manual add always works. Plan changes broadcast to update the
list automatically, but the list survives a missing plan, a missing pantry, and a
missing connection to the LLM. Checking an item writes a `Pantry.add_item` (closed
loop, see §5).

### Settings (`/settings`)

- Family preferences (diet, cuisines, kid constraints, weekly cadence).
- **Kitchen Memory:** the list of active family insights with per-insight "this is
  wrong" buttons that dismiss without deletion.
- Read-only pantry view ("Here's what we think you have"), reachable from here.
- Device tokens for kiosks.
- Per-user accounts.

### Costs (out of main nav)

Reachable from Settings → "Spending." Not weekly viewing. The receipts table and
monthly totals stay; the dashboards drop in priority.

---

## Removed in Rewrite

The following exists in the codebase today and is **deleted** by this spec. Implementation
plans must remove these explicitly — they are not deprecated, they are gone.

| Removed | Replacement |
|---------|-------------|
| `pantry_live.ex` full CRUD (add/edit/category management UI) | Read-only inferred pantry view in Settings; receipt + grocery + photo-scan auto-add |
| `/pantry` in main nav | Removed entirely |
| `/costs` in main nav | Moved under Settings |
| `Tore.Family` context (introduced as the canonical name in the prior rewrite) | `Tore.Household` is canonical; `Tore.Family.*` deleted |
| `CounterNotes.build_home_note/1` hardcoded "Ready to cook tonight?" string | `AmbientScan` daily job |
| Two-step `confirm_receipt` UI as the only receipt → pantry path | Auto-add by default; confirm flow stays only for explicit "review before saving" |
| Onboarding questionnaire (if/when added) | Inference from events over time |
| Any meal-rating or "how was dinner?" UI | Never built; explicitly prohibited |
| Any "you haven't logged in N days" reminder | Never built; explicitly prohibited |

---

## Module Map (target state)

```
lib/tore/
  household.ex               # canonical household context (preferences, members, insights)
  household/
    household_schema.ex
    household_insight.ex
    preferences.ex
  accounts.ex                # users, sessions
  recipes.ex
  deals.ex
  pantry.ex                  # inference-shaped: list, add_item, remove_item, last_seen_at
  costs.ex
  prep.ex
  groceries/                 # Decider aggregate
  planning/                  # Decider aggregate
    commands.ex              # AssignRecipe, SwapRecipe, SkipMeal, ...
    events.ex                # MealSkipped, RecipeRemoved, RecipeSwapped, ...
    decider.ex
    state.ex
  counter_notes.ex
  counter_notes/
    counter_note.ex
  ai_operations.ex
  chat/
    chat_handler.ex
    system_prompt.ex         # injects family prefs, insights, week context, approx pantry
    week_context.ex
  llm.ex                     # behaviour (chat, chat_with_tools, all Pattern A callbacks)
  llm/
    prompts.ex               # JSON schemas + EEx prompt templates
    planner_agent.ex         # NEW: tool-calling loop runtime for §2
    planner_tools.ex         # NEW: tool definitions (action + read)
  adapters/
    open_router.ex           # implements chat_with_tools via OpenRouter tool API
  handlers/
    planning_handler.ex
    groceries_handler.ex
    recipe_handler.ex
    pantry_handler.ex
    deals_handler.ex
    prep_handler.ex
    costs_handler.ex         # MUST close the loop to pantry
    insights_handler.ex      # weekly synthesis
  jobs/
    ambient_scan.ex          # NEW: daily rule scan (replaces deleted home_note.ex)
  photo_pipeline.ex
  scheduler.ex
  storage.ex
```

```
lib/tore_web/live/
  home_live.ex
  planner_live.ex            # adds command bar that drives PlannerAgent
  chat_live.ex               # completes fridge → suggestions flow
  kiosk_live.ex
  kiosk_chat_live.ex
  cooking_live.ex
  grocery_live.ex            # close loop: check → Pantry.add_item
  recipe_live.ex
  deals_live.ex
  prep_live.ex
  settings_live.ex           # kitchen memory + read-only pantry
  review_live.ex
  login_live.ex
  setup_live.ex
  # REMOVED: pantry_live.ex from main routing (kept only as Settings-reachable read-only view)
  # MOVED: cost_live.ex under settings scope
```

---

## LLM Surface

Every LLM call goes through the `Tore.LLM` behaviour and is logged to `AIOperations`
with a correlation ID. Required callbacks for the AI-native target state:

| Callback | Purpose |
|----------|---------|
| `chat/2` | Free-form chat with system prompt |
| `chat_with_tools/4` | **NEW.** Tool-calling chat. Powers `PlannerAgent` (§2). |
| `generate_plan/1` | Weekly plan generation |
| `suggest_recipe/2` | Single-slot suggestion |
| `synthesise_insights/1` | Weekly observations from event summary |
| `parse_receipt_image/1` | Vision: receipt → line items |
| `parse_recipe_image/1` | Vision: recipe → structured recipe |
| `parse_pantry_image/1` | Vision: shelf → items |
| `classify_image/1` | Vision: route any uploaded photo |
| `identify_fridge_contents/1` | **NEW.** Vision: fridge → ingredient list |
| `cook_mode_steps/1` | Compress recipe steps for cooking surface |

**Spend guard:** `Tore.SpendGuard` continues to gate every LLM call. The monthly
budget is enforced at the adapter boundary. Each iteration of a `chat_with_tools`
loop is counted as a separate call against the budget.

---

## LLM Interface Conventions

Two patterns, used deliberately:

### Pattern A — Structured Output (default for parsers and extractors)

Used by every callback whose job is *"turn this input into a fixed-shape result"*:
`parse_receipt_image`, `parse_recipe_image`, `parse_pantry_image`,
`identify_fridge_contents`, `synthesise_insights`, `generate_plan`, `suggest_recipe`,
`cook_mode_steps`.

- Implementation: OpenAI-compatible `response_format: %{type: "json_schema", json_schema: %{name:, strict: true, schema:}}`.
- Schemas live in `Tore.LLM.Prompts` next to the prompt EEx files.
- `strict: true` is mandatory — the adapter must reject any non-conforming output rather than best-effort parsing.
- One LLM round-trip per call. No loops. No tool registration.

### Pattern B — Tool-Calling Agent (for in-app actions)

Used when the LLM needs to *do something* in the app — read state, then write state,
possibly across several turns. V1 has one consumer: `PlannerAgent` (§2). Future
candidates (grocery agent, prep agent) reuse the same pattern.

- Implementation: `chat_with_tools(system, messages, tools, opts)`. The adapter passes `tools` straight through to the model's tool-calling API.
- Tools are defined declaratively as `%{name, description, parameters_schema, kind: :action | :read, run: (args -> result)}`. The agent runtime, not the adapter, executes them.
- Tool schemas use JSON Schema and are validated before the tool's `run` function is invoked. Invalid tool calls are reported back to the LLM as a tool error message; the loop continues.
- The agent runtime enforces: max round-trips, max action calls, sequential execution for actions, parallel allowed for reads.
- Every round-trip is one `AIOperations` row, sharing a `correlation_id` with `step_index` for the sequence.
- The model is `tools`-capable on OpenRouter (e.g. `anthropic/claude-3.5-sonnet` or `openai/gpt-4o-mini`). The model choice is per-callback and configurable.

### When to use which

- **Parser, extractor, classifier, or "summarise this":** Pattern A. Always.
- **The LLM needs to look something up that wasn't pre-stuffed into the prompt:** Pattern B.
- **The LLM needs to perform actions that change app state and might require multiple steps:** Pattern B.
- **Anything new that doesn't clearly fit:** Pattern A first. Escalate to Pattern B only when a concrete use case shows single-shot can't reach the goal.

### Universal rules

- Every call logs to `AIOperations` with `model`, `prompt_tokens`, `completion_tokens`, `correlation_id`, and `step_index` (always 0 for Pattern A).
- Every call is gated by `Tore.SpendGuard` at the adapter boundary.
- No LLM-emitted SQL, no LLM-emitted code execution, no LLM-emitted shell. Tool surface is the only side-effect channel.
- The system prompt is built by a single `Tore.Chat.SystemPrompt.build/1` to keep prefs/insights/week context consistent across callbacks.

---

## Quantum Schedule (target state)

```elixir
config :tore, Tore.Scheduler,
  jobs: [
    {"0 7 * * *",   {Tore.Jobs.AmbientScan,             :run,                []}},
    {"0 3 * * *",   {Tore.Deals,                        :clear_expired,      []}},
    {"0 6 * * 6",   {Tore.Handlers.InsightsHandler,     :synthesise_weekly,  []}},
    {"0 8 * * 6",   {Tore.Handlers.DealsHandler,        :scrape_all,         []}},
    {"0 18 * * 6",  fn -> Tore.Handlers.PlanningHandler.generate_plan("plan:current", Date.utc_today()) end},
    {"30 18 * * 6", fn -> Tore.Handlers.PrepHandler.generate_guide("plan:current", Date.utc_today()) end},
  ]
```

The existing `home_note` job (Tore.Jobs.HomeNote, 06:00) is **removed** — `AmbientScan`
subsumes it.

---

## Auth and Multi-Tenancy

A *household* owns all data: plans, groceries, pantry, costs, insights.
*Users* belong to a household. A user is created with a 16-digit code; sessions are long-lived browser cookies.
*Kiosks* authenticate with a per-device token, scoped to one household.
`Tore.Household` is the canonical context. There is no `Tore.Family` module.

---

## Out of Scope for This Spec

- iOS/Android native apps. Mobile web is the target.
- Multi-family aggregation, social/sharing features.
- Nutrition tracking, calorie counting.
- Voice input (target for a later phase; the command bar is text-only initially).
- Anything that requires push notifications.

---

## Success Criteria

The rewrite is done when:

1. The six LLM-native features (§1–§6) each pass an end-to-end test on a real device.
2. `pantry_live.ex` no longer offers add/edit; the route is gone from main nav.
3. `cost_live.ex` is reachable only through Settings.
4. `Tore.Family.*` is deleted; `Tore.Household` is canonical.
5. `PlannerAgent` runs a bounded tool-calling loop driven from the planner command bar, with all action tools wired through `PlanningHandler` and at least two read tools (`search_recipes`, `pantry_snapshot`) wired to real context state.
6. `AmbientScan` runs daily and writes at least one counter-note type when the
   corresponding rule fires.
7. Receipts uploaded via chat write to both `costs` and `pantry` without a confirm
   step (the confirm path remains for explicit review).
8. Fridge photos return three concrete recipe suggestions.
9. A user can skip a meal with one tap and the app says nothing back.
10. No notifications. No nags. No streaks.
