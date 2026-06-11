# Tore — AI-Native Meal Planner & Kitchen Kiosk

> *Tore* is a self-hosted family meal planner. The previous incarnation was *Scullion*,
> a competent but conventional CRUD-shaped planner. This document specifies the
> AI-native rewrite. Where this spec disagrees with the codebase, this spec wins.

## Status

- **Source-of-truth date:** 2026-05-30
- **2026-05-31:** Reversed the Family→Household naming. `Tore.Household` is canonical; `Tore.Family.*` deleted.
- **2026-06-02:** Added §Agent Harness Layer. Tore is reframed as a household food-operations harness; every state-changing AI action is a `KitchenRun` producing typed artifacts, verified deterministically, applied atomically. §The Six LLM-Native Features rewritten in harness terms. Future sub-specs implement the harness primitives, verifiers, capsules, risk tiers, resolved references, and Kitchen Skills.
- **2026-06-02:** UI/UX vocabulary adopted. Canonical names: `CounterNote` (artifact and code module — replaces the working name `Opportunity` from the first draft of §A), `Shop` (UI surface and route `/shop` — replaces `Groceries` / `/groceries`), `Capture` (UI surface and route `/capture` — replaces `Chat` / `/chat`), `Tore.Capture` (module namespace — replaces `Tore.Chat`). The code rename is a separate sub-plan; SPEC.md uses the new names throughout from this commit forward.
- **Supersedes:** the original Scullion SPEC.md (2026-05-02), now archived in git history at commit `af0ad48`.
- **Companion docs:** `LLM-NATIVE-FEATURES.md` (the design brief this spec absorbs), `UI_SPEC.md` (UI/UX contract — meets this spec at the artifact boundary), `PLAN.md` (module-by-module breakdown), `PLAN_FEAT_*.md` (per-feature plans).
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
| **Shop** | Multi-user real-time grocery checklist (decider stream `shop`, formerly `groceries`). Granular events enable PubSub sync and natural undo. |

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
| **CounterNotes** | Ambient suggestions surfaced inline on Home/Plan/Kiosk as `CounterNote` artifacts. See §3. |
| **KitchenRuns** | Bounded AI operations (see §Agent Harness Layer). Each run owns multiple `AIOperations` rows by correlation ID. |
| **AIOperations** | Low-level audit log of every LLM call with correlation IDs, step index, model, and token usage. |

---

## Agent Harness Layer

### A.1 — Tore is a household food-operations harness

Tore is not a chatbot over meal-planning data. Tore is a small, tasteful harness
around the household food loop.

A coding agent feels powerful because it doesn't just answer — it runs a bounded
operation, produces a diff, verifies it, and lets you accept or reject. The model
is one component of a larger scaffold: typed context, permissioned tools,
structured prompts, execution traces, verification, and reversible state. The
harness is what turns "chat with file access" into something a careful engineer
will trust.

Tore applies the same shape to food. Every non-trivial AI action is a bounded
run with a typed input snapshot, declared context, permissioned tools, generated
artifacts, deterministic verification, and a clean reversible diff. The LLM
proposes. The harness verifies. The user sees a quiet, tasteful receipt — not a
transcript.

The rest of this section names the parts of that harness: runs, artifacts,
capsules, verifiers, risk tiers, resolver tools, skills, inspectability, and
model routing. Every feature in §The Six LLM-Native Features below is then
re-described as a kind of run.

### A.2 — The unit is a `KitchenRun`

Every non-trivial AI action in Tore is a `KitchenRun`. A run is the food
equivalent of an agentic coding session: a bounded operation with a typed
beginning, a verified middle, and a reversible end. `AIOperations` continues
to record the low-level LLM-call audit log; a single `KitchenRun` owns one or
more `AIOperations` rows tied by `correlation_id`.

**Fields:**

- `id`
- `household_id`
- `kind` — one of the declared run kinds (see §The Six LLM-Native Features)
- `status` — `:draft | :running | :needs_user | :applied | :failed | :reverted`
- `phase` — when `status: :running`, one of `:gathering_context | :proposing | :verifying`; `nil` otherwise. Drives the UI's operational thinking-state strip (UI_SPEC §7.2) — *"Checking the week…", "Looking at deals…", "Verifying changes…"*
- `started_by` — `:user | :scheduler | :ambient_scan | :opportunity_followup`
- `surface` — `:home | :plan | :shop | :chat | :kiosk`
- `input_snapshot` — the typed input the run was started with
- `capsules_used` — the named context capsules the run requested (see §A.4)
- `tool_trace` — the ordered sequence of tool calls, args, and results
- `proposed_changes` — diff candidates produced by the loop, not yet committed
- `applied_events` — the event-store events actually appended (the reversible audit trail)
- `artifacts` — the typed `RunArtifact`s the run produced (see §A.3)
- `verification_results` — pass/fail per verifier (see §A.5)
- `model_usage` — token counts and cost rolled up across owned `AIOperations`
- `undo_ref` — a pointer the UI can call to revert the run's applied events
- `created_at`, `completed_at`

**Lifecycle.** A run starts in `:draft`. The harness builds the requested
capsules, dispatches the loop, and the run moves to `:running`. If the LLM
calls `ask_user` (or any human-gate tool), the run becomes `:needs_user` and
pauses — the surface shows the question, the run resumes when the user
answers. If verifiers pass and tool results commit, the run is `:applied`.
If verifiers fail unrecoverably, the run is `:failed`, no applied events
remain, and the surface shows a repair state. The user can revert any
`:applied` run to `:reverted` via the `undo_ref`, which appends compensating
events.

**Hard rules.**

- Only a `KitchenRun` may write to event-sourced aggregates (planning, groceries) on the AI's behalf — direct adapter calls outside a run are forbidden.
- Every state-changing AI action shows up as a row in the kitchen runs table.

### A.3 — Runs produce `RunArtifact`s, not chat output

A `KitchenRun` does not produce a conversational reply. It produces one or
more `RunArtifact`s — typed, renderable objects with a compact summary and an
inspectable detail view. Artifacts are the contract between the harness and
the UI: the harness emits them, the UI surfaces them, and neither side knows
how the other implements its half.

**Artifact kinds:**

| Kind | Produced by | Carries |
|---|---|---|
| `PlanDiff` | `:planner_command_run`, `:weekly_planning_run` | Per-slot changes with before-and-after recipe handles |
| `GroceryDiff` | `:weekly_planning_run`, `:grocery_reconciliation_run` | Added / removed / quantity-changed items with source recipe attribution |
| `PrepGuide` | `:prep_generation_run` | Ordered prep steps tied to slots with dependencies |
| `RecipeSuggestions` | `:fridge_rescue_run`, `:planner_command_run` | Ranked recipe handles with one-line rationales |
| `RecipeProposal` | `:recipe_ingestion_run` (URL / text / photo), `:recipe_generation_run` (prompt) | A parsed-or-generated recipe shown before commit; user can edit; commit writes to catalog |
| `PantryBeliefUpdate` | `:receipt_ingestion_run`, `:pantry_belief_update_run` | Items added / removed / `last_seen_at` bumped, with provenance |
| `CostEntry` | `:receipt_ingestion_run` | Parsed receipt: store, date, total, line items, optional photo path |
| `DealsUpdate` | `:deal_capture_run` | New deals parsed from a flyer photo, with provenance `:vision` |
| `MemoryUpdate` | `:kitchen_memory_synthesis_run` | Insights added / superseded / unchanged, with evidence pointers |
| `CounterNote` | `:ambient_scan_run`, `:deal_opportunity_run` | A proposed action with title, body, `proposed_run` link, primary + dismiss actions |
| `RunSummary` | every run | One-line human-readable description plus structured `counts` (e.g. `%{meals_changed: 4, grocery_items_updated: 17, prep_notes_added: 1}`); always present |

**Renderable contract.** Every artifact must support two render modes:

- **Summary** — at most one short line for the run-receipt strip, plus a structured `counts` map. The UI assembles the summary string from `counts` using a small renderer (e.g. *"4 meals changed · 17 grocery items updated · 1 prep note added"*), so spacing, separators, and pluralisation are UI concerns and never the harness's prose. The harness guarantees the numbers; the UI guarantees the prose.
- **Detail** — a structured view the user opens deliberately. Example: the full `PlanDiff` shown as before-and-after slots, with a per-slot rationale.

The UI never reads run internals. It reads artifacts. A new UI surface that
wants to show, say, the planner's proposed changes opens the `PlanDiff`
artifact from the latest `:applied` run.

**No chat transcripts in artifacts.** The LLM's prose replies are recorded in
`tool_trace` for the audit log and the inspector, but are never the primary
rendering. A run that produces only a chat-shaped string with no typed
artifact is a harness bug.

**Hard rule.** Every `:applied` or `:needs_user` `KitchenRun` carries at least
one artifact (always a `RunSummary`, often a domain artifact too). A run with
zero artifacts is invalid.

### A.4 — Context capsules, not one big prompt

Today the LLM gets a single system prompt assembled by
`Tore.Chat.SystemPrompt.build/0` — household preferences, active insights,
week context, and approximate pantry, all glued together. As the harness
grows, that builder becomes a junk drawer: every new feature adds another
paragraph, every prompt becomes longer, and no caller can tell which inputs
actually drove a model's behaviour.

A `KitchenRun` receives a small set of named, typed **context capsules**.
Each capsule is compact, audited, and declared per run — never inferred from
the surrounding code, never assembled by string concatenation.

**Capsule catalog (V1):**

| Capsule | Provides | Source |
|---|---|---|
| `HouseholdPreferencesCapsule` | Diet, allergies, dislikes, cuisines, kid constraints, default servings, planning days | `Tore.Household.get_preferences/0` |
| `ActiveInsightsCapsule` | Active `HouseholdInsight` rows, prose + structured fields | `Tore.Household.list_active_insights/0` |
| `WeekPlanCapsule` | The current or referenced week's plan state, per slot | `Tore.Handlers.PlanningHandler.load_plan/1` |
| `PantryBeliefsCapsule` | Approximate inventory with `last_seen_at` and provenance; framed as belief, not fact | `Tore.Pantry.list_inventory/0` |
| `DealsDigestCapsule` | Active deals grouped by store, ranked by household affinity | `Tore.Deals.list_current/0` + `RecipeAffinityCapsule` |
| `RecipeAffinityCapsule` | Recipes the household chose recently or repeatedly, plus those swapped or removed | derived from planning event stream |
| `RecentHistoryCapsule` | Last 4–6 weeks of meals, skipped slots, leftover cascades | derived from planning event stream |
| `CostIntentCapsule` | Monthly spend target, current month-to-date, recent overspend signal | derived from `Tore.Costs` + household preferences |

**Declaration rule.** Every run kind declares its capsules statically. A
capsule the run did not request is not available to its prompt — there is no
"ambient" context. This is auditable: looking at a run, you can answer
"what did the model see?" without reading code.

**Capsule shape.** A capsule is a struct, not a string. It has typed fields
(e.g. `pantry_items :: [%{name, last_seen_at, provenance}]`) and a
`to_prompt/1` function that produces the compact text the model receives. UI
and verifiers can read the struct directly without re-parsing prose.

**Compactness.** Each capsule has a token budget. If `RecipeAffinityCapsule`
returns 200 recipes, it summarises to the top 20 + a count. The summarisation
rule lives in the capsule, not in the run.

**Hard rules.**

- No run dispatches to `chat_with_tools/4` or any structured-output callback without an explicit capsule list.
- No code outside `lib/tore/harness/capsules/` may stuff data into a system prompt. `Tore.Chat.SystemPrompt.build/0` is deleted; its callers move to declaring capsules on a run.
- A new feature that wants a new kind of context adds a capsule. It does not extend an existing capsule with "and also this."

### A.5 — Verifiers run after every state-changing run

A coding agent earns trust by running tests. Tore's harness earns trust the
same way: every state-changing `KitchenRun` is checked by a deterministic
verifier before its `applied_events` are committed. The LLM proposes. The
verifier decides if the proposal can actually land. The user sees a clean,
validated result — never a half-applied edit.

Verifiers are pure code, not LLM calls. They read the run's
`proposed_changes` and the current state of the affected aggregates, and
return either `:ok` or a structured `:fail` reason. They do not call models,
do not have side effects, and are cheap to run inline at the end of every
run.

**Verifier catalog (V1):**

| Verifier | Owns | Checks |
|---|---|---|
| `PlanVerifier` | `PlanDiff` | No locked/pinned slot was changed; every assigned recipe has servings; leftover slots point to a valid source meal earlier in the week; skipped slots are explicit, not missing; no banned ingredient or dietary constraint is violated; no recipe appears twice within the household's configured repeat window |
| `GroceryVerifier` | `GroceryDiff` | Every removed item was added by a recipe (manual user adds are never AI-removed); every added quantity has a unit; pantry deductions use approximate inventory and never assume hard zero |
| `PrepVerifier` | `PrepGuide` | Every prep step points to a slot in the current plan; prep dependencies are scheduled before the dependent meal, not after; no step references a recipe not in the plan |
| `PantryVerifier` | `PantryBeliefUpdate` | Provenance is set on every item write; no negative quantities; `last_seen_at` is monotonic per item |
| `RecipeProposalVerifier` | `RecipeProposal` | Title, ingredients (≥1), and instructions are present; servings is positive; no near-duplicate of an existing catalog recipe (title + ingredient overlap heuristic); no ingredient name is empty |
| `CostEntryVerifier` | `CostEntry` | Store, date, total are present; line items sum within tolerance of total; date is not in the future |
| `DealsUpdateVerifier` | `DealsUpdate` | Every deal has product name, price, store, source; `valid_until` is set or defaults to 14 days; no duplicate of a still-active scraped deal |
| `MemoryVerifier` | `MemoryUpdate` | New insights have `kind`, `confidence`, and `evidence_count`; superseded insights link to a successor; no more than the configured maximum active insights per household |
| `CounterNoteVerifier` | `CounterNote` | Title and body present; `proposed_run` is a declared run kind; primary action is a valid event the harness can dispatch; rationale list non-empty |

**Verifier lifecycle.** A run's loop ends. The harness collects
`proposed_changes` from the loop's `tool_trace`, runs the appropriate
verifiers, and one of three things happens:

- **All pass.** The harness commits `applied_events` to the event store, persists artifacts, transitions the run to `:applied`, and surfaces the run receipt.
- **One or more fail.** No events commit. The run transitions to `:failed`. Each verifier failure stores both a structured `code` (e.g. `:slot_locked`, `:ingredient_missing`, `:dup_recipe_in_repeat_window`) and a `user_message` field — a short, human-readable sentence that names what blocked the action without exposing tool-call internals or blaming the model. The surface shows a compact repair state with the `user_message`, a verifier-specified `repair_action` (a `proposed_run` link or a manual-edit affordance), and a dismiss option. *Example: "The salmon reference matched two recipes."* The verifier owning the failure is responsible for both fields.
- **Run hit a human gate mid-loop.** The verifier did not get a chance to run. The run is `:needs_user`; verification happens after the user answers.

**No partial applies.** A verifier failure is atomic — nothing commits. This
is the load-bearing rule. The run is either fully applied or not applied;
the user is never asked to clean up a half-edited week.

**No model retry on verifier failure.** When verification fails, the harness
does not silently re-run the LLM with the verifier reason in the prompt.
That path is tempting (cheap retry, often fixes the failure) but it hides
bugs and produces non-deterministic spend. The repair state is surfaced to
the user; they decide whether to retry.

**Hard rules.**

- Every run kind that produces a state-changing artifact has at least one verifier in this table. A run kind that doesn't is a harness bug.
- Verifiers run inside the harness, not inside the LLM tool layer. The LLM never sees verifier failure reasons during a run.
- Verifier failures are stored on the `KitchenRun` row for later inspection; a verifier that fails 20% of the time across runs is a signal to fix the tool, the prompt, or the verifier — not to retry harder.

### A.6 — Risk tiers, resolved references, and Kitchen Skills

#### A.6.1 — Risk tiers

Every `KitchenRun` kind is classified into one of four tiers. The tier
determines whether the harness auto-applies, surfaces for inspection, or
requires explicit confirmation before any event commits.

| Tier | Examples | Apply policy |
|---|---|---|
| **Tier 0 — Surface only** | `:ambient_scan_run`, `:deal_opportunity_run` | The run produces `CounterNote` artifacts but writes no aggregate state on its own. The user opts in by tapping a primary action, which dispatches a follow-up run of higher tier. |
| **Tier 1 — Reversible domain edits** | `:planner_command_run`, `:weekly_planning_run`, `:prep_generation_run`, `:fridge_rescue_run`, `:pantry_belief_update_run`, `:kitchen_memory_synthesis_run` | Auto-apply after verifier passes. The run receipt is visible. Undo is one tap. |
| **Tier 2 — Reversible ingestion** | `:receipt_ingestion_run`, `:deal_capture_run`, `:recipe_ingestion_run`, `:grocery_reconciliation_run` | Auto-apply by default, but the proposal artifact is always surfaced as a card the user can review and edit before commit. Becomes `:needs_user` per the rule below. |
| **Tier 3 — Destructive or sensitive** | `:recipe_generation_run`; bulk operations like *clear the week*; any change touching dietary constraints or allergens | Never auto-applies. Proposal is produced; commit requires explicit user confirmation. |

A Tier 2 run becomes `:needs_user` (proposal surfaced as an editable card
before commit) when **any** of the following holds:

- **Item count.** The proposal touches more than 5 line items.
- **Confidence.** Any item in the proposal has resolver confidence below 0.8 (the resolver-handle threshold from §A.6.2 is 0.7 for action-tool acceptance; 0.8 is the higher bar for trust-without-review).
- **Provenance.** The run's input was a `:vision` source (photo) rather than `:scrape` or `:manual`.

**Hard rules.**

- Tier classification lives on the run-kind declaration. It is not a runtime decision; the model cannot escalate or de-escalate.
- Tier 3 is the only tier with a confirm modal. Tier 0–2 use act-then-undo. The UI never asks "are you sure?" for Tier 1 or 2.
- A run that touches household preferences (diet, allergies) is Tier 3 regardless of its declared kind.

#### A.6.2 — Resolved references, never raw IDs

The LLM never passes a raw aggregate ID to an action tool. State changes
happen through **resolver tools** that return typed handles with provenance,
and action tools that accept those handles.

A handle is a struct:

```elixir
%ResolvedRecipe{
  id: "recipe_123",
  label: "Salmon pasta",
  source: :search_recipes,        # which resolver produced it
  confidence: 0.91,
  resolved_in_run: "run_abc"      # the KitchenRun that resolved it
}
```

The same shape applies to `ResolvedSlot`, `ResolvedGroceryItem`,
`ResolvedPantryItem`, `ResolvedDeal`. Every handle carries `source`,
`confidence`, and the run that resolved it.

**Resolver tools (V1):**

- `resolve_slot(reference :: String.t())` — natural-language slot reference (`"tonight"`, `"Tuesday lunch"`, `"the salmon slot"`) → `ResolvedSlot` or `:ambiguous` with candidates.
- `resolve_recipe(reference :: String.t())` — fuzzy recipe match by title or attribute → `ResolvedRecipe` or `:ambiguous`.
- `resolve_grocery_item(reference :: String.t())` — match by name + unit against the current list → `ResolvedGroceryItem`.
- `resolve_pantry_item(reference :: String.t())` — match against approximate inventory → `ResolvedPantryItem`.

**Action tools take handles, not IDs:**

```elixir
assign_recipe(slot_handle, recipe_handle, servings?)
swap_recipe(from_slot_handle, to_slot_handle)
```

If a resolver returns `:ambiguous`, the LLM is expected to call `ask_user`
rather than guess. The harness will not accept an action tool call with an
unresolved or invented handle: any handle whose `resolved_in_run` is not the
current run is rejected.

**Hard rules.**

- Action tools may not accept raw IDs. The Tool struct's parameter schema rejects an `integer` where a handle is expected.
- A handle's `confidence` below the per-tool threshold (default 0.7) is treated as ambiguous — the action tool refuses and the LLM must call `ask_user` or rerun the resolver with more specificity.
- The same handle may be reused within a single run but not across runs. The harness re-validates the handle's `resolved_in_run` on every action call.

#### A.6.3 — Kitchen Skills

A Kitchen Skill is a reusable agent runbook: a pre-declared `KitchenRun`
kind with its capsules, tools, verifier, and target artifact set. Skills are
how the user invokes a higher-order operation without typing a free-text
command.

Each skill is a small typed declaration. The skill catalog is the V1 surface
of the harness for ordinary household operations.

**V1 skill catalog:**

| Skill | Dispatches | Purpose |
|---|---|---|
| `PlanMyWeek` | `:weekly_planning_run` | Generate the upcoming week from current pantry, deals, insights, and past affinity |
| `UseTheDeals` | `:weekly_planning_run` (deal-weighted) | Re-plan the week prioritising current active deals |
| `LowEnergyWeek` | `:weekly_planning_run` (low-effort weighted) | Plan a week of short-cook recipes with cascading leftovers |
| `StretchLeftovers` | `:planner_command_run` | Re-arrange the current week to maximise leftover cascades |
| `RescueTheFridge` | `:fridge_rescue_run` | Photo or pantry snapshot → recipe suggestions that use what's there |
| `SundayPrep` | `:prep_generation_run` | Generate a prep guide for the upcoming week |
| `FinishTheShoppingList` | `:grocery_reconciliation_run` | Reconcile grocery list with the plan and add anything missing |
| `LearnFromThisWeek` | `:kitchen_memory_synthesis_run` | Force an out-of-schedule memory synthesis from recent events |

The runbook fields (`trigger`, `capsules`, `tools`, `verifier`, `artifact`,
`surface`) live in a future Skills sub-spec. The umbrella names the concept
and the V1 list only.

**Surface rule.** Skills appear in the UI as small contextual action chips
on the surfaces where they are relevant (e.g. `PlanMyWeek` on Plan;
`RescueTheFridge` on Capture). There is no global "skills" management screen.

**Hard rule.** A skill is just a pre-declared `KitchenRun` kind with bound
parameters. It is not a separate primitive. Removing a skill is removing a
row from the catalog, not a refactor.

### A.7 — Inspectability

Every `RunArtifact` produced by a `KitchenRun` carries enough information
for the user to ask *why this?* and get a concrete answer. Inspectability is
not a separate logging or telemetry layer — it is a contract on the artifact
shape.

**Each artifact field that drove a user-visible decision must carry its
rationale inline.**

Examples:

- A `PlanDiff` slot change carries a `rationale` field: `"Pork on sale at ICA · matches a high-affinity recipe · Tuesday has no prep dependency"`.
- A `CounterNote` carries an `evidence` list: `["yoghurt last seen 6 days ago", "chicken marinade recipe uses yoghurt", "chicken slot empty Wednesday"]`.
- A `RecipeSuggestion` carries a `rationale` per recipe: `["uses leftover salmon", "30 min total", "household chose this 3× in the last 8 weeks"]`.
- A `PantryBeliefUpdate` carries `provenance` per item: `:receipt`, `:grocery_checkoff`, `:shelf_photo`, `:manual`.

Rationale strings are produced by the run, not by the LLM at render time.
They reflect what actually drove the decision: the capsule fields the model
read, the deals it weighted, the insights it cited. A rationale that says
only *"the model picked it"* is a harness bug.

**UI contract.** The surface always renders the artifact's summary form by
default. The rationale and evidence are revealed on a deliberate inspect
gesture. The harness guarantees the data is there; UI/UX spec decides the
affordance.

**Hard rules.**

- Every artifact field that surfaces a decision carries a rationale or provenance.
- Rationales are short and concrete — not paragraphs, not LLM prose. The verifier owning the artifact checks rationale presence as part of artifact validity.
- A run that produces an artifact with empty rationales fails its verifier. There is no "the model didn't explain" fallback.

### A.8 — Model routing

The harness routes LLM calls to one of three model tiers based on the
callback's pattern (§LLM Interface Conventions) and the run kind's risk tier
(§A.6.1). Routing is per-callback, not per-feature. The model used on each
call is recorded on `AIOperations.model` for cost telemetry.

**Model tiers (V1):**

| Tier | Use cases | Default model class |
|---|---|---|
| **Cheap structured** | Pattern A callbacks that parse, classify, or summarise: `classify_image`, `parse_receipt_image`, `parse_pantry_image`, `parse_deals_image`, `cook_mode_steps`, ambient-scan summarisations, capsule `to_prompt/1` token reductions | A fast small model with reliable strict-JSON support |
| **Strong tool-capable** | Pattern B `chat_with_tools/4` for `:planner_command_run`, `:weekly_planning_run`, `:grocery_reconciliation_run`, `:fridge_rescue_run`, and any future skill-driven run that calls multiple tools across multiple turns | A frontier tool-calling model |
| **Vision** | Any callback whose primary input is an image: `classify_image`, `parse_receipt_image`, `parse_recipe_image` (when input is a photo), `parse_pantry_image`, `parse_deals_image`, `identify_fridge_contents` | A vision-capable model; may overlap with "cheap structured" when the structured-output is small |

Concrete model names are configured per tier in runtime config, not
hard-coded in callsites. Today's `openrouter_model`, `openrouter_vision_model`
config keys remain; new keys `openrouter_strong_model` and
`openrouter_cheap_model` join them.

**Fallback rule.**

- **Pattern A schema-validation failure.** A structured-output callback whose response fails strict schema validation retries **once** with the strong-tier model. If that also fails, the call returns `{:error, :schema_unsatisfiable}` and the parent run records the failure. No third attempt.
- **Pattern B tool-loop failure.** A `chat_with_tools/4` run whose verifier fails does **not** auto-retry with a stronger model. The repair state surfaces to the user (§A.5).

**No per-feature routing.** A skill or run kind cannot override the model
tier its callbacks would normally use. This rules out the "this feature
deserves the strong model" creep that produces opaque cost lines on the
bill.

**Hard rules.**

- Every `Tore.LLM` callback is statically annotated with its model tier. The annotation is read at runtime by the adapter; there is no per-call model override.
- `AIOperations.model` is set on every row. Cost rollups on `KitchenRun.model_usage` aggregate by tier across the run's owned operations.
- The schema-failure single-retry path is the only place the harness silently uses a different model than the callback declared. The retry is logged distinctly (`AIOperations.kind` ends with `.retry`). The monthly `SpendGuard` cap remains the runaway-cost guard.

### A.9 — Meeting point with UI_SPEC.md

This spec owns the harness contract: run kinds, artifact shapes, capsule
declarations, verifier checks, risk tiers, resolver handles. `UI_SPEC.md`
owns the surface contract: how artifacts render across Today / Plan / Shop /
Capture / Cooking / Kiosk / Settings, the visual system, the run-receipt and
thinking-state and failure-state and undo and "Why this?" patterns.

The two specs meet at artifact schemas. Concretely:

- `RunSummary.counts` (§A.3) drives UI_SPEC §7.1's run-receipt pluralisation and §5.2's receipt card body.
- `KitchenRun.phase` (§A.2) drives UI_SPEC §7.2's operational thinking-state strip.
- Verifier failures' `user_message` + `repair_action` (§A.5) drive UI_SPEC §7.3's failure-state card.
- Per-item `rationale` and `evidence` on every artifact (§A.7) drive UI_SPEC §7.5's "Why this?" expansion.
- `CounterNote` fields `title`, `body`, `primary_action`, `dismiss_action` (§A.3) drive UI_SPEC §5.2's counter-note card.
- `RecipeProposal` fields drive UI_SPEC §6.4's capture-result preview.
- `MemoryUpdate.evidence_count` drives UI_SPEC §5.2's memory card "Seen 7 times" line.

When UI_SPEC adds a surface that needs an artifact field this spec didn't
name, that's a SPEC.md amendment, not a UI-side workaround. When this spec
declares a field that no UI surface consumes, that's a SPEC.md trimming
opportunity. Both specs evolve together at the artifact-schema boundary; no
side silently degrades.

---

## The Six LLM-Native Features

Each feature is re-described here as one or more `KitchenRun` kinds with their
capsules, tools, artifacts, verifier, risk tier, and model tier. All six are
required; none is optional.


### 1. Longitudinal Learning → `:kitchen_memory_synthesis_run`

A weekly Quantum job (Sat 06:00) starts a `:kitchen_memory_synthesis_run`. It
reads the planning event stream from the last 28 days and produces a small set
of typed observations about how the household actually eats.

- **Capsules:** `ActiveInsightsCapsule`, `RecentHistoryCapsule`, `RecipeAffinityCapsule`.
- **Tools:** none — Pattern A structured-output call.
- **Artifact:** `MemoryUpdate` (insights added / superseded / unchanged, with evidence pointers per insight).
- **Verifier:** `MemoryVerifier` (kind, confidence, evidence_count present; max active count respected; superseded insights link forward).
- **Tier:** 1 — reversible. Dismissed insights are tombstoned; follow-up synthesis won't recreate them.
- **Model tier:** cheap structured.

Inputs the synthesis considers: `MealSkipped` events grouped by weekday →
*"skips Thursdays 7/10 weeks"*; `RecipeRemoved` and `RecipeSwapped` → dislikes
and friction; `LeftoverDay` patterns → which cascades survive; slot fill rate
by week → *"rarely plans past Wednesday"*.

Storage: `household_insights` table — small (max ~10 active observations per
household), with structured fields (`kind`, `subject`, `claim`,
`evidence_count`, `confidence`, `last_evidence_at`) plus a prose `prompt_text`
used by capsules. A `dismissed_at` field tombstones rather than deletes; a
`superseded_by_id` link preserves history.

The user sees the active insights on Settings → Kitchen Memory and can dismiss
any insight that's wrong.

**Hard rule:** There is no rating UI. There is no *"how was dinner?"* prompt.
The event stream is the only signal.

### 2. Natural-Language Planner → `:planner_command_run`

The user types into the planner command bar. The harness starts a
`:planner_command_run`.

- **Capsules:** `HouseholdPreferencesCapsule`, `ActiveInsightsCapsule`, `WeekPlanCapsule`, `PantryBeliefsCapsule`, `DealsDigestCapsule`, `RecentHistoryCapsule`.
- **Tools:** resolver tools (`resolve_slot`, `resolve_recipe`, `resolve_grocery_item`); action tools that take handles (`assign_recipe`, `swap_recipe`, `skip_meal`, `mark_leftover`, `set_servings`, `remove_recipe`); read tools (`search_recipes`, `pantry_snapshot`, `active_deals`); terminal `ask_user`.
- **Artifacts:** `PlanDiff` (always), `RecipeSuggestions` (when a read tool surfaces candidates), `RunSummary`.
- **Verifier:** `PlanVerifier`.
- **Tier:** 1 — auto-apply with undo. The run receipt is the user-facing confirmation.
- **Model tier:** strong tool-capable (Pattern B).

**Loop caps** (enforced by the harness): 6 LLM round-trips per utterance, 12
action-tool calls per utterance (read tools don't count). Action tools run
sequentially in call order. An action-tool error is fed back to the LLM; the
model decides whether to retry, alter the plan, or call `ask_user`.

**Resolver-handle rule** (§A.6.2). Action tools take `ResolvedSlot` /
`ResolvedRecipe` handles, never raw IDs. A resolver returning `:ambiguous`
forces the LLM to call `ask_user` rather than guess.

Every loop iteration is logged to `AIOperations` with the run's
`correlation_id` and a per-call `step_index`. The required LLM callback
`chat_with_tools/4` is specified in §LLM Interface Conventions.

**Hard rules.**

- Buttons still work. NL is the power path; it is never the only path.
- The LLM cannot read or write anything outside the registered tool surface. No direct DB access from prompts, no template-expanded pantry dumps mid-loop.
- The agent never silently guesses an ambiguous reference. *"The salmon"* matching two recipes forces `ask_user`. The harness enforces this by rejecting unresolved handles.

### 3. Proactive Intelligence → `:ambient_scan_run` + `:deal_opportunity_run`

A daily Quantum job (07:00) starts an `:ambient_scan_run`. A post-scrape
trigger (after the weekly deal scrape completes) starts a
`:deal_opportunity_run`. Both produce `CounterNote` artifacts.

- **Capsules:** `WeekPlanCapsule`, `PantryBeliefsCapsule`, `DealsDigestCapsule`, `RecentHistoryCapsule`, `RecipeAffinityCapsule`, `ActiveInsightsCapsule`.
- **Tools:** none — Pattern A structured-output calls.
- **Artifacts:** zero or more `CounterNote`s, each with `kind`, `title`, `body`, `proposed_run` (the run kind dispatched when the user taps the primary action), primary + dismiss actions, and an evidence list.
- **Verifier:** `CounterNoteVerifier`.
- **Tier:** 0 — surface only. The runs never mutate aggregate state. State mutation happens when the user taps the primary action, which dispatches a follow-up Tier 1+ run with `started_by: :opportunity_followup`.
- **Model tier:** cheap structured.

**`CounterNote` kinds (V1):**

| Kind | Trigger | Proposed run |
|---|---|---|
| `:expiring_pantry_match` | Pantry item expiring in ≤3 days AND a catalog recipe uses it AND that recipe is not in the current plan | `:planner_command_run` to assign the recipe to a near slot |
| `:cascade_break` | A cascade plan depends on Sunday prep but Sunday slot is empty/unplanned | `:planner_command_run` to fill the source slot |
| `:unplanned_week` | It is Wednesday or later AND the current week has ≥3 unplanned dinners | `:weekly_planning_run` |
| `:deal_match` | A deal matches a high-affinity recipe (frequently chosen, never swapped) | `:planner_command_run` to assign the matched recipe |

New kinds are added by extending the catalog, not by new run kinds.

**Hard rule.** `CounterNote`s appear inline on the relevant surface. They are
never delivered as push, email, or any other interruption.

### 4. Pantry as Inference → `:pantry_belief_update_run`

Every implicit channel that updates pantry inventory dispatches a
`:pantry_belief_update_run`: grocery item checked off, chat shelf photo
scanned, manual edit in Settings.

- **Capsules:** `PantryBeliefsCapsule` (the current state, framed as belief).
- **Tools:** vision callback `parse_pantry_image/1` for photo inputs; no tools for grocery checkoff (the run is deterministic in that case).
- **Artifact:** `PantryBeliefUpdate` (items added / removed / `last_seen_at` bumped, each with `provenance` ∈ `:receipt | :grocery_checkoff | :shelf_photo | :manual`).
- **Verifier:** `PantryVerifier`.
- **Tier:** 1 (grocery checkoff, manual) or 2 (shelf photo — vision input → editable card surfaces if ≥5 items or low confidence per §A.6.1).
- **Model tier:** vision (photo input only).

**Demotion in detail (still required):**

- The `/pantry` route is removed from main nav.
- `pantry_live.ex` is a read-only *"Here's what we think you have"* view reachable from Settings. One action: remove an item. No add. No edit.
- Adding to the pantry happens via three implicit channels: checked-off grocery items, parsed receipts (§5), photo-of-shelf via chat.
- The `PantryBeliefsCapsule` frames inventory as approximate. Items carry `last_seen_at` and `provenance`. A capsule that says *"the household has olive oil"* is replaced by *"probably has olive oil, last seen 3 weeks ago via receipt"*.

**Hard rule.** Spec or implementation work that adds back a primary
pantry-management screen is a regression of this requirement.

### 5. Receipt → Pantry Closed Loop → `:receipt_ingestion_run`

A receipt photo uploaded through chat dispatches a `:receipt_ingestion_run`.

- **Capsules:** none — the input is the image; no household state required for parsing.
- **Tools:** `parse_receipt_image/1` (vision). The run then dispatches a sub-write: cost log + pantry write.
- **Artifacts:** `CostEntry` (the parsed receipt) AND `PantryBeliefUpdate` (each line item with `provenance: :receipt`) — both from one run.
- **Verifiers:** `CostEntryVerifier` AND `PantryVerifier`. Either failure fails the whole run; atomic apply (§A.5).
- **Tier:** 2 — auto-apply if ≤5 line items AND confidence ≥0.8 per §A.6.1; otherwise `:needs_user` with editable line-item card.
- **Model tier:** vision.

This is the closed loop: one user action (upload photo), two outputs
(`CostEntry` + `PantryBeliefUpdate`), one verifier set, one undo button.

### 6. Fridge Photo → Suggestions → `:fridge_rescue_run`

A chat photo classified as `:fridge` dispatches a `:fridge_rescue_run`.

- **Capsules:** `HouseholdPreferencesCapsule`, `WeekPlanCapsule` (so suggestions don't duplicate tonight's plan), `RecipeAffinityCapsule`.
- **Tools:** `identify_fridge_contents/1` (vision); `search_recipes` (read); `assign_recipe` (action, optional — user may tap *"add to tonight"* from a suggestion).
- **Artifact:** `RecipeSuggestions` (3 ranked recipes with rationale).
- **Verifier:** none for the suggestions themselves (Tier 0 — read-only). If the user taps *"add to tonight,"* a follow-up `:planner_command_run` dispatches with `PlanVerifier`.
- **Tier:** 0 — purely informational.
- **Model tier:** vision (initial photo) + strong tool-capable (suggestion ranking).

Today the chat replies *"Want me to suggest some recipes?"* and stops. The
harness completes the run and surfaces the `RecipeSuggestions` artifact
inline.

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
- FAB → `/capture`.

### Planner (`/plan`)

- Week view with editable slots.
- Counter notes for surface `plan` at the top.
- A command bar at the bottom: text input + voice (phase ≥ 8) that runs through `PlannerAgent` (§2).
- Slot interactions still work via tap (assign, swap, skip, mark leftover, set servings).

### Capture (`/capture`)

Full-screen capture surface that accepts text and photos. Photos are classified
(`receipt | recipe | pantry_items | fridge | unknown`) and routed to the
appropriate run kind. The capture surface is a way to start a `KitchenRun`,
not a conversation thread: each capture produces a typed artifact (see §A.3)
and the surface renders it, not a chat reply.

### Shop (`/shop`)

The reliability anchor. Manual add always works. Plan changes broadcast to
update the list automatically, but the list survives a missing plan, a
missing pantry, and a missing connection to the LLM. Checking an item
dispatches a `:pantry_belief_update_run` (see §4).

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
  shop/                      # Decider aggregate
  planning/                  # Decider aggregate
    commands.ex              # AssignRecipe, SwapRecipe, SkipMeal, ...
    events.ex                # MealSkipped, RecipeRemoved, RecipeSwapped, ...
    decider.ex
    state.ex
  counter_notes.ex           # context for CounterNote artifacts (formerly the build_home_note stub home)
  counter_notes/
    counter_note.ex
  ai_operations.ex           # low-level LLM call audit log; owned by KitchenRun
  harness/                   # NEW (foundation sub-spec): the Agent Harness Layer
    kitchen_run.ex           # the central KitchenRun context (start, persist, transition, undo)
    run_kinds.ex             # declared run kinds with capsules, tools, verifier, tier, model_tier
    artifact.ex              # RunArtifact behaviour and registered kinds
    capsules/                # one file per capsule kind
      household_preferences_capsule.ex
      active_insights_capsule.ex
      week_plan_capsule.ex
      pantry_beliefs_capsule.ex
      deals_digest_capsule.ex
      recipe_affinity_capsule.ex
      recent_history_capsule.ex
      cost_intent_capsule.ex
    verifiers/               # one file per verifier
      plan_verifier.ex
      grocery_verifier.ex
      prep_verifier.ex
      pantry_verifier.ex
      recipe_proposal_verifier.ex
      cost_entry_verifier.ex
      deals_update_verifier.ex
      memory_verifier.ex
      counter_note_verifier.ex
    skills.ex                # V1 Kitchen Skills catalog
    resolvers.ex             # resolve_slot, resolve_recipe, resolve_grocery_item, resolve_pantry_item
    handles.ex               # ResolvedSlot, ResolvedRecipe, etc.
  llm.ex                     # behaviour (chat, chat_with_tools, all Pattern A callbacks)
  llm/
    prompts.ex               # JSON schemas + EEx prompt templates
    planner_agent.ex         # tool-calling loop runtime; refactored to emit a KitchenRun
    planner_tools.ex         # tool definitions take handles, not raw IDs
  adapters/
    open_router.ex           # implements chat_with_tools via OpenRouter tool API
  handlers/
    planning_handler.ex
    groceries_handler.ex
    recipe_handler.ex
    pantry_handler.ex
    deals_handler.ex
    prep_handler.ex
    costs_handler.ex         # closes the loop to pantry inside :receipt_ingestion_run
    insights_handler.ex      # weekly synthesis run dispatcher
  jobs/
    ambient_scan.ex          # daily rule scan; dispatches :ambient_scan_run
  photo_pipeline.ex
  scheduler.ex
  storage.ex
```

```
lib/tore_web/live/
  home_live.ex
  planner_live.ex            # adds command bar that drives PlannerAgent
  capture_live.ex            # completes fridge → suggestions flow
  kiosk_live.ex
  kiosk_capture_live.ex
  cooking_live.ex
  shop_live.ex               # close loop: check → Pantry.add_item
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
11. Every state-changing AI action is a `KitchenRun` — visible as a row in the kitchen runs table, owning its `AIOperations` rows, carrying its declared capsules, producing its typed artifacts, gated by its verifier, classified into a risk tier. No code path mutates an event-sourced aggregate on the AI's behalf outside a run.
12. Every Tier 1+ run produces at least one `RunArtifact` (always a `RunSummary`, often a domain artifact) with rationale-or-provenance fields populated. A run that produces empty rationales fails its verifier and does not commit.
