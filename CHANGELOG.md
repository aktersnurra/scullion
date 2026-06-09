# Changelog

All notable changes to Tore are recorded here. The app is pre-production, so
entries are grouped by feature milestone rather than released versions.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Harness foundation

The event-sourced run harness — the load-bearing primitives for AI-driven
runs.

- `Tore.Harness.Run` aggregate: closed `Events`/`Commands` sum types (10 each),
  a six-variant `State` ADT enforced by `@enforce_keys`, and a pure
  `Decider` (`decide/2` + `evolve/2`).
- `Tore.Harness.Run` public surface: `load/1`, `next_stream_id/0`, and
  `append/3` (PubSub-broadcasting on the household topic).
- Closed `Artifact` behaviour + compile-time `Registry`, with the `PlanDiff`
  (events authoritative, `summarise/1` projection) and `RunSummary`
  (outcome + counts rollup) artifacts.
- `Tore.Harness.Orchestrator`: composes the Decider, owns persistence and
  artifacts, drives the planner command run.
- Per-household `Tore.Harness.Projector` (GenServer + ETS, replays open runs on
  boot) with its Registry and DynamicSupervisor.
- `Tore.LLM.PlannerAgent.run/4` refactored to a pure bounded tool-calling loop
  (no persistence, no correlation-id generation).
- `ai_operations`: `correlation_id` replaced with `run_stream_id` (irreversible
  migration).
- Web: `ReceiptLive` component (pattern-matched per `State` variant); `PlannerLive`
  consumes the Projector and renders the receipt, replacing the old
  `quick_reply` machinery.

### Real PlanDiff from tool outcomes

The receipt now reflects what the planner actually did, not a placeholder.

- `Tore.Harness.PlanDiffBuilder` reconstructs a real `PlanDiff` from the
  planner's successful tool calls (joining args to results by `tool_call_id`,
  keeping only successful action calls); the Orchestrator uses it instead of a
  hardcoded placeholder.
- New `PlanDiff` event types `RecipeSwapped` and `ServingsChanged` in the
  rollup; humanized `RunSummary`/`PlanDiff` change wording.
- Action tools require a `rationale` arg (flows into each diff event);
  `assign_recipe`/`swap_recipe` return the recipe label.
- `PlanningHandler.swap_slots/3`: a true atomic recipe swap (reads both slots
  before cross-assigning) — fixes a data-loss bug where the old move-based swap
  destroyed the target recipe.

### Named receipt lines + Swedish i18n

- The receipt's applied body renders one localized line per change, naming the
  recipe and day (from the `PlanDiff` rollup), e.g. "Bytte in Ugnsraggmunk på
  Lördag" / "Hoppade över Söndag".
- Plan-health badge localized via `{status, count}` + a view-side `gettext`
  helper (domain module stays web-free).
- Full Swedish translation pass: all remaining UI strings translated, 8 wrong
  fuzzy auto-matches corrected.
- Receipt component tests pinned to the `sv` locale so they assert what users
  actually see.

### Orchestrator error boundary

- `dispatch/2` is railway-oriented end to end with a typed error channel
  (`{:step_failed, term} | {:run_crashed, Exception.t}`): interior helpers
  thread `{:ok,_} | {:error,_}` (no more bare matches that raised), a
  `try/rescue` at the boundary converts any crash, and a best-effort tee records
  the run as `Failed` on any error — no dangling open runs.
- The receipt translates `failure_code` (machine-readable) instead of a baked
  message string; Swedish failure messages added.

### Verify-then-mutate planner + PlanVerifier

The planner is now verify-then-mutate, closing the load-bearing §A.5 atomicity
gap: the LLM proposes, a deterministic verifier decides, and a failure leaves
the plan genuinely unchanged.

- Planner action tools are pure: they propose plan changes against an in-memory
  working `Planning.State` via the existing `Planning.Decider` (preserving the
  model's mid-loop `:slot_empty`/`:not_pinned` feedback) and return the events
  they'd produce plus the evolved state — no persistence. `swap_recipe` reuses
  an extracted pure `PlanningHandler.swap_events/3`.
- `PlannerAgent` threads a `working_plan` through its loop and accumulates
  `plan_events`, returning both in its `loop_outcome`. The Orchestrator loads the
  plan into the agent context and persists the accumulated events exactly once,
  after the loop, via `PlanningHandler.apply_events/2`.
- `Tore.Harness.Verifier.PlanVerifier` — deterministic gate over the planner's
  `PlanDiff` (pinned slot unchanged, every assigned recipe has servings, skips
  are explicit, leftovers point to an earlier source meal, no banned/allergen/
  disliked ingredient). First failure wins. The repeat-window check is deferred
  (it needs a `repeat_window` household preference — a product decision; faking a
  default would be less correct than not checking).
- The Orchestrator gates the plan apply on the verifier: pass → apply + commit;
  fail → record the run as `Failed` with a structured `code` and an
  `{:edit_plan, slots}` repair action, applying nothing. A verifier failure is a
  successful dispatch of a failed run, not an infrastructure error.
- Web: the receipt renders a per-code, localized (en/sv) failure message and an
  "Edit the plan" link; the planner reads a `focus` query param and highlights
  the offending slot(s), completing the repair loop.

### Context capsules (§A.4)

The junk-drawer system prompt is replaced by typed, per-run-declared context
capsules — the model's standing context is now auditable ("what did the model
see?" = the run's capsule list), independently testable, and free of ambient
string concatenation.

- `Tore.Harness.Capsule` behaviour (`build/1` + `to_prompt/1`) and
  `Tore.Harness.Capsules.compose/2` — the only assembler; a capsule a run did
  not list is not in its prompt.
- Four capsules with a real consumer today, each a typed struct that fetches and
  summarises its own data (the compactness rule lives in the capsule):
  `HouseholdPreferencesCapsule`, `ActiveInsightsCapsule` (≤5),
  `WeekPlanCapsule` (typed per-day status), `PantryBeliefsCapsule`
  (names capped at 20 + a count).
- The planner run and the chat handler now declare their capsule list and
  compose it; the date and active week-mode stay as small inline framing. The
  planner's doubled role section (its own preamble plus the chat role text) is
  removed.
- `Tore.Chat.SystemPrompt.build/0` deleted — fully replaced by capsules.

### Fixed

- Event-store JSON round-trip downgraded atom/Decimal event fields on replay;
  `Run.load` now rehydrates them (`cost_usd` → Decimal; `phase`/`surface`/
  `step_kind` and `RunSummary` outcome/count keys → atoms via explicit closed
  maps, load-order independent to survive cold-boot Projector replay).
- `PlannerAgent` assigned a unique `step_index` per trace entry (was colliding,
  violating the `ai_operations` unique constraint) and coerces a float
  `cost_usd` from the LLM into a Decimal.
- Planner dispatch in `PlannerLive` clears the spinner and flashes on failure
  instead of hanging on a silent crash.
- `FailureRecorded` round-trip: `repair_action` is encoded as a map on write and
  decoded back to `{:edit_plan, slots}` via a literal map on read, and
  `failure_code` decodes via a literal map for the known verifier codes — both
  cold-boot safe (no `String.to_existing_atom`), so a fresh Projector boot can't
  downgrade a verifier code to a string the receipt would fail to match.
