# A.5 Verifiers — PlanVerifier Design

**Date:** 2026-06-08
**Spec section:** SPEC.md §A.5 (Verifiers run after every state-changing run)
**Scope:** The first verifier — `PlanVerifier` — and the verify→commit-or-fail
gate it plugs into, for the one shipped run kind (`:planner_command_run`).

## Goal

Close the load-bearing harness gap. Today `Orchestrator.close/4` enters the
`:verifying` phase and then commits the planner's `PlanDiff`
**without running any verifier**. A locked slot can be clobbered, a recipe can
be assigned with no servings, a leftover can point at nothing, and an allergen
can land on the plate — with nothing checking. SPEC §A.5 is explicit: *"a run
kind that produces a state-changing artifact and has no verifier is a harness
bug."*

This sub-spec installs the gate: a deterministic `PlanVerifier` that runs after
the planner loop, **blocks the commit atomically** on failure, records the run
as `Failed` with a structured `code` and a spec-faithful manual-edit
`repair_action`, and surfaces a localized repair state with planner slot-focus.

## Non-goals

- No other verifiers (`GroceryVerifier`, `PrepVerifier`, …). Only `PlanVerifier`,
  matching the one shipped run kind.
- No generic `Verifier` behaviour / registry. One concrete module. The contract
  gets extracted when the second verifier lands, informed by two real cases.
- No model retry on verifier failure (SPEC §A.5 hard rule). The repair state is
  surfaced; the user decides whether to re-drive.

## Architecture — the gate

The change is localized to `Orchestrator.close/4`. Today both the `:message` and
`:capped` result clauses do: build `PlanDiff` → `AddArtifact(diff)` →
`AddArtifact(summary)` → `Commit`. We insert one verify step **before** the
artifacts and commit:

```
build PlanDiff
  → PlanVerifier.verify(plan_diff, verify_ctx)
      :ok                        → AddArtifact(diff) → AddArtifact(summary) → Commit
      {:fail, code, repair}      → RecordFailure{code: code,
                                                  user_message: nil,
                                                  repair_action: repair}
```

Both clauses (`:message`, `:capped`) gain the same gate. The `{:question, q}`
clause is unchanged — a run that hit a human gate mid-loop is `:needs_user`;
verification happens after the user answers (SPEC §A.5, third lifecycle case).

### Correctness properties

- **Atomic, no partial apply.** On `{:fail, …}` the code never reaches
  `AddArtifact`/`Commit`, so nothing is appended to the event store. The run
  transitions straight to `State.Failed`. This is the load-bearing rule from
  §A.5: the run is fully applied or not applied; the user is never asked to
  clean up a half-edited week.
- **Verifier failure is a successful dispatch of a failed run — not a dispatch
  error.** `close/4`'s fail branch returns `{:ok, failed_state}`, not
  `{:error, {:step_failed, _}}`. A verifier failure is a normal, expected
  outcome that legitimately reaches the terminal `Failed` state with the
  verifier's real `code`. The typed `dispatch_error`
  (`{:step_failed, _} | {:run_crashed, _}`) stays reserved for genuine
  infrastructure failures.
- **The existing error boundary still wraps everything.** `verify/2` is called
  inside the existing `with` chain under `try/rescue`. A *raised* verifier bug
  becomes `{:run_crashed, _}` → `record_failure/2` records `:internal_error`,
  exactly like any other step. A *clean* verifier failure is distinct: a
  deliberate `RecordFailure` carrying the verifier's structured code.
- **No model retry.** We record `Failed` and stop. There is no silent re-run of
  the LLM with the verifier reason in the prompt (§A.5 hard rule).

## PlanVerifier

New module `Tore.Harness.Verifier.PlanVerifier`. Pure-ish: deterministic reads
only — no writes, no model calls. (A DB read is side-effect-free in the sense
§A.5 cares about: no mutation, no LLM, cheap, deterministic.)

```elixir
@type repair_action :: {:edit_plan, [String.t()]}
@type fail_code ::
        :slot_pinned
        | :servings_missing
        | :skip_not_explicit
        | :leftover_no_source
        | :dietary_violation

@spec verify(PlanDiff.t(), verify_ctx) :: :ok | {:fail, fail_code, repair_action}
```

### Verify context

`verify_ctx` is a map the Orchestrator assembles before calling `verify/2`:

```elixir
%{
  plan_state: Tore.Planning.State.t(),   # PlanningHandler.load_plan(plan_stream_id) — post-diff plan
  preferences: Tore.Household.Preferences.t()  # dietary_restrictions + allergies + dislikes
}
```

`plan_state` carries `slots` (slot_key → %{recipe_id, servings, skipped,
leftover}) and `pins` (slot_key → pin), both already present on the aggregate.

### Checks

Run in fixed order; return the **first** failure (deterministic, one repair
affordance at a time). Each failure carries the offending slot_keys for the
deep-link.

| # | Check | Data source | Fail code |
|---|---|---|---|
| 1 | No pinned slot was changed | `plan_state.pins` keys ∩ diff slot_keys | `:slot_pinned` |
| 2 | Every assigned recipe has servings (`RecipeAssigned` / `ServingsChanged` payloads have a positive integer `servings`) | diff payloads | `:servings_missing` |
| 3 | Skipped slots are explicit — every `MealSkipped` event targets a slot that exists in the plan, not a silently-missing one | diff `MealSkipped` vs. `plan_state.slots` | `:skip_not_explicit` |
| 4 | Leftover points to a valid source meal **earlier in the week** — every `LeftoverMarked` slot has an assigned (non-skipped, non-leftover) source slot ordered before it | diff `LeftoverMarked` + slot ordering | `:leftover_no_source` |
| 5 | No banned/allergen/dietary-violating ingredient in any assigned recipe — load each `recipe_id` and intersect its ingredient names against `preferences.dietary_restrictions ++ allergies ++ dislikes` | diff `recipe_id`s → `Recipes` lookup | `:dietary_violation` |

The verifier owns **codes and slot_keys only** — no user-facing copy (wording
lives in the receipt, see below). `nil`/empty results pass.

#### Slot ordering (check 4)

Slot keys are `"<day>_<meal>"` (e.g. `"mon_dinner"`). Order is the weekday order
`mon < tue < wed < thu < fri < sat < sun`, meal as a tiebreaker if both share a
day. A leftover slot is valid iff at least one slot earlier in this order has a
`recipe_id` and is neither `skipped` nor `leftover`. Use the **post-diff**
`plan_state`, so a recipe assigned in the same run counts as a valid source.

### Deferred check (written reason)

SPEC §A.5 lists a sixth `PlanVerifier` check: *"no recipe appears twice within
the household's configured repeat window."* **It is deliberately not implemented
in this sub-spec.** The check needs a `repeat_window` value, and:

- It is **not in the schema.** `Household.Preferences` has no such field.
- It is **not derivable.** `planning_days` (5 or 7) is plan length, not a repeat
  tolerance.
- It is a **genuine product decision** (same week? N days? across weeks?). The
  SPEC wrote "configured" precisely because there is no obvious right answer.

Implementing it against a fabricated default constant would be *less* correct
than not checking — it would silently block real plans based on a number nobody
chose, defeating the trust the verifier exists to earn. The honest path is a
small follow-up sub-spec that first adds a `repeat_window` household preference
(migration + changeset + default + settings affordance), then adds check 6 to
`PlanVerifier` against it. This is recorded as deferred, not dropped.

## Failure surfacing & the repair affordance

### 1. `repair_action` data shape and round-trip

`State.Failed` already carries `failure_code`, `failure_user_message`, and
`failure_repair_action`, plumbed through `FailureRecorded` → `to_failed/2`.
Today `failure_repair_action` round-trips as a bare atom via `Run.rehydrate/1`'s
`safe_atom/1`. It becomes a tagged tuple `{:edit_plan, [slot_key]}`.

This crosses the event store as JSON. A `{:edit_plan, slots}` tuple **cannot**
be `Jason`-encoded (tuples are not valid JSON), so a write-side encoder is
**required**, not optional — `FailureRecorded` must convert the tuple to a map
before it reaches the store, mirroring how `prepare/1` already special-cases
`ArtifactAdded`. (This is the atom round-trip hazard already hit twice in this
codebase.)

- **Write side (`Run.prepare/1`):** add a clause for `%Events.FailureRecorded{}`
  that serializes `repair_action: {:edit_plan, slots}` →
  `%{"action" => "edit_plan", "slots" => slots}`; `nil` stays `nil`.
- **Read side (`Run.rehydrate/1`):** the existing `FailureRecorded` clause
  reconstructs the tuple from the map via an **explicit literal map** on
  `"action"` (`"edit_plan" -> :edit_plan`), **not** `String.to_existing_atom`,
  for cold-boot safety (the Projector replays open runs at boot before dependent
  modules load — same reason `step_kind_atom`, `phase_atom`, `surface_atom` use
  literal maps). `nil` passes through. The current `safe_atom(event.repair_action)`
  call is replaced by this map-based decoder.

`failure_code` stays an atom via the existing `safe_atom/1` path — the five new
codes (`:slot_pinned`, etc.) are module attributes on `PlanVerifier`, loaded by
the time a planner run fails, so `safe_atom` resolves them; the `rescue` keeps
it from crashing on an unknown string.

### 2. Receipt rendering (`ToreWeb.Components.ReceiptLive`)

- `failure_message/1` gains one clause per code, each a localized sentence
  (gettext) that names what blocked the action without exposing tool internals
  or blaming the model (§A.5):
  - `:slot_pinned` → *"That day is pinned, so Tore left it as it was."*
  - `:servings_missing` → *"A meal was missing servings, so nothing was changed."*
  - `:skip_not_explicit` → *"Tore couldn't tell which day to skip."*
  - `:leftover_no_source` → *"There was no earlier meal to make leftovers from."*
  - `:dietary_violation` → *"A suggested recipe didn't fit your household's needs."*
  - existing `:internal_error` and the catch-all fallback stay.
- A new repair-link element: when the Failed run's `failure_repair_action` is
  `{:edit_plan, slots}`, render an "Edit the plan" link (gettext) navigating to
  the planner with the slots as a query param. The dismiss option already
  exists for the Failed state.
- Swedish translations added for every new msgid, **stripping the `fuzzy` flag**
  after filling each msgstr (the fuzzy trap — gettext ignores fuzzy at runtime
  and renders the English msgid; test env runs in `sv`).

### 3. Planner slot focus (`ToreWeb.Live.PlannerLive`)

- Accept a `focus` query param: `/plan?focus=mon_dinner,fri_dinner`.
- On mount/`handle_params`, parse it into a `focused_slots` MapSet assigned to
  the socket.
- The slot template adds a highlight class for slots in `focused_slots`, plus a
  `phx-hook` (or `JS` scroll command) that scrolls the first focused slot into
  view. This is the net-new UI that realizes the full manual-edit affordance.

## Files

```
New:    lib/tore/harness/verifier/plan_verifier.ex
Modify: lib/tore/harness/orchestrator.ex          # verify gate in both close/4 clauses; assemble verify_ctx
        lib/tore/harness/run.ex                    # prepare/1 encodes repair_action tuple; rehydrate/1 decodes via literal map
        lib/tore_web/components/receipt_live.ex     # per-code failure_message clauses + edit link
        lib/tore_web/live/planner_live.ex           # focus param → focused_slots → highlight + scroll
        priv/gettext/en/LC_MESSAGES/default.po
        priv/gettext/sv/LC_MESSAGES/default.po
New:    test/tore/harness/verifier/plan_verifier_test.exs
Modify: test/tore/harness/orchestrator_test.exs    # verifier-fail integration + happy path still commits
        test/tore_web/components/receipt_live_test.exs  # per-code message + edit link (sv assertions)
        test/tore_web/live/planner_live_test.exs    # focus param highlights slots
```

## Testing

- **PlanVerifier unit tests** (pure, table-driven): for each of the 5 codes, one
  passing case and one failing case, asserting the exact
  `{:fail, code, {:edit_plan, slots}}`. Check 5 (dietary) uses real `Recipes`
  fixtures with a known allergen/restriction.
- **Orchestrator integration:** `MockLLM` drives a loop whose `PlanDiff`
  violates a pin → assert the run ends `State.Failed`, `failure_code:
  :slot_pinned`, **no `Committed` event**, **no plan mutation** (the plan
  aggregate is unchanged). Plus: the happy path (no violation) still commits and
  reaches `:applied`.
- **Round-trip:** a `FailureRecorded` carrying `{:edit_plan, [...]}` survives
  `Run.load` (cold-boot atom safety — reconstructed via the literal map).
- **ReceiptLive:** a Failed run renders the correct localized message per code
  and the edit link with the correct href; gettext `sv` assertions.
- **PlannerLive:** the `focus` param produces highlighted slots in the rendered
  view.

## Open follow-ups (out of scope)

- Add `repeat_window` household preference + `PlanVerifier` check 6.
- The remaining V1 verifiers (`GroceryVerifier`, `PrepVerifier`, …) as their run
  kinds ship; extract a shared `Verifier` contract once a second implementer
  exists.
