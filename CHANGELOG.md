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
