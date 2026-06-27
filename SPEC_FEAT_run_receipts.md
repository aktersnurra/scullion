# SPEC_FEAT_run_receipts — Reversible agent actions with run receipts

> Companion to SPEC.md (§Agent Harness) and UI_SPEC.md (§7.1, §16).
> This spec defines the backend work that makes the doctrine in UI_SPEC §16
> actually buildable.

## Status

- **Created:** 2026-06-24
- **Model:** agent acts immediately; user undoes if wrong.
  Not approval-gated proposals. Trust comes from visibility + reversibility.
- **Scope:** the BE artifacts and machinery the UI needs in order to render
  run receipts, support Undo, surface belief states, and respect user locks.
- **Out of scope:** the UI work itself (UI_SPEC owns that), the Today/Plan/Shop
  visual rebuild (separate phase).

### Relationship to the KitchenRun harness (SPEC.md §A)

This spec is **a vertical slice of the KitchenRun harness**, focused on the
user-visible half: the receipt, the diff, the undo. It is not a parallel
track or a replacement — it is the first concrete run kind, shipped before
the full harness (capsules, verifiers, resolvers, risk tiers, model
routing) is built out.

Vocabulary alignment:

| This spec | SPEC.md §A KitchenRun | Notes |
|---|---|---|
| `RunReceipt` | `KitchenRun` + `RunSummary` artifact | Receipt is the user-facing rendering; KitchenRun is the full audit row. As the harness lands, RunReceipt becomes a view over KitchenRun, not a separate table. |
| `DiffRow` | `PlanDiff`, `GroceryDiff`, `PantryBeliefUpdate` (typed per-domain) | DiffRow is the simpler cross-surface shape that ships first. The typed per-domain artifacts come in later when verifiers need them. |
| `UndoHandle` (sum type) | `KitchenRun.undo_ref` | Same idea; this spec names the encoding (`:event_sourced` / `:snapshot` / `:composite` / `:irreversible`). |
| Belief state on PantryItem | `PantryBeliefsCapsule` framing (SPEC.md §4) | Same model. This spec lands the column; the capsule reads it. |
| Plan-slot locks | `PlanVerifier` "no locked slot was changed" check | This spec adds the events + projection; the verifier consumes them when it lands. |
| Tool classification (`:silent` / `:diff_row` / `:own_receipt`) | Run-kind declaration in `run_kinds.ex` | First pass at risk-tier-adjacent classification. Will fold into formal Tier 0–3 (SPEC.md §A.6.1) later. |

**Module layout.** Implementation lands under `lib/tore/harness/` (per
SPEC.md §Module Map), not a freestanding `lib/tore/receipts/` tree. Phase 1
scaffolds the harness directory with run_receipts as its first occupant:

```
lib/tore/harness/
  run_receipt.ex        # Ecto schema (this spec)
  run_receipt_diff.ex   # Ecto schema (this spec)
  undo_handle.ex        # sum-type encoding (this spec)
  run_receipts.ex       # context: record/1, get/1, undo/2 (this spec)
  # later, as the harness expands:
  kitchen_run.ex
  run_kinds.ex
  artifact.ex
  capsules/
  verifiers/
  resolvers.ex
  handles.ex
```

When the full `KitchenRun` schema lands, `RunReceipt` rows migrate to or
become a projection over `KitchenRun` rows. The migration cost is small
because the field overlap (id, household_id, intent, applied_at,
correlation_id, undo handle) is high.

**What this slice does NOT yet require:**

- Capsules (SPEC.md §A.4). The Capture Router still uses its current
  prompt-building path. Capsule extraction comes later.
- Verifiers (SPEC.md §A.5). Receipts ship without verifier gating; the
  reversibility-via-Undo property substitutes for verifier-blocked-commit
  in the interim. Verifiers land before Tier 3 (destructive) runs do.
- Resolver handles (SPEC.md §A.6.2). Tools still take strings/ids for now.
  Handle conversion is a follow-up phase.
- Risk tiers (SPEC.md §A.6.1). Tool classification (§7 below) is the
  proto-tier; formal Tier 0–3 mapping comes when verifiers do.
- Model routing (SPEC.md §A.8). Current single-model routing continues.

These deferred pieces are tracked in SPEC.md as the long-term harness;
nothing in this spec contradicts them.

---

## 1. Why this spec exists

UI_SPEC §16 says every agent-driven state change must produce a run receipt
that the user can Undo. The current backend doesn't support this end-to-end:

- Agent tools in `Tore.Capture.Router` mutate plan/shop/pantry directly and
  return prose. The Router emits Capture bubbles, not durable receipts.
- There is no undo handle on most agent mutations. The reversible-diff idea
  exists in SPEC.md (§Agent Harness, "reversible diff") but is not wired
  through tool calls.
- Pantry rows are quasi-boolean. There is no belief-state field the UI can
  read to render `? probably at home`.
- Plan slots have no `locked_by_user` field. The agent has no way to know
  it must skip a user-pinned slot.
- KitchenRun exists for some flows (receipt_ingestion, pantry_belief_update,
  recipe_normalisation) but not for arbitrary capture-driven tool sequences.

Without these, the UI either lies (renders confidence it doesn't have),
loses the user's intent (overwrites locks), or makes Undo impossible.

## 2. The model

```
┌──────────────────────────────────────────────────────────────────┐
│ Capture turn                                                     │
│ user input → Router → tool calls                                 │
│                                                                  │
│ Each tool call that mutates state:                              │
│   1. Records the mutation as a RunReceipt entry                  │
│   2. Stores an undo handle (event ids / before-state snapshot)   │
│   3. Returns a structured DiffRow list to the Router             │
│                                                                  │
│ The Router emits ONE RunReceipt bubble per turn aggregating      │
│ all DiffRows from that turn.                                     │
└──────────────────────────────────────────────────────────────────┘
```

A turn produces at most one RunReceipt. Multiple tool calls within a turn
collapse into one receipt with grouped diff rows. Undo undoes the whole turn.

## 3. Artifacts

### 3.1 RunReceipt

A durable record of one agent turn's mutations. Persisted (not just in
LiveView assigns) so it can be re-rendered, listed in a future Needs-Review
inbox, and undone after a page refresh.

```
RunReceipt
  id                  uuid
  household_id        fk
  user_id             fk         (the user who triggered the turn)
  trigger             enum       (:capture_text, :capture_photo,
                                  :receipt_commit, :scheduled, :manual)
  intent              string     (one-line summary, e.g. "Add 3 dinners")
  diff_rows           [DiffRow]
  assumptions         [string]   (e.g. "Assumed olive oil at home")
  undo_handle         UndoHandle (nil if not reversible)
  undo_expires_at     datetime   (nil if undo is unlimited)
  applied_at          datetime
  reverted_at         datetime?  (set when Undo is invoked)
  correlation_id      string     (matches KitchenRun if applicable)
```

### 3.2 DiffRow

One line in a receipt. The four prefixes from UI_SPEC §16.4 (`+`, `-`, `~`, `?`)
map to the `op` field.

```
DiffRow
  op           enum   (:added, :removed, :changed, :assumed)
  surface      enum   (:plan, :shop, :pantry, :recipe, :prep, :cost)
  label        string (human-facing, household language)
  before       any?   (only for :changed)
  after        any?   (only for :added, :changed)
  reason       string? (one-line; renders as small text below row)
```

The DiffRow is what the UI renders. It does not carry ids or DB references;
that's what UndoHandle is for.

### 3.3 UndoHandle

What the system needs to reverse the turn. Implementation depends on the
target context:

```
UndoHandle (sum type)
  | :event_sourced   stream_id, event_ids[]  (Plan, Shop)
  | :snapshot        table, row_id, before_attrs  (Pantry, Recipes)
  | :composite       [UndoHandle]  (when a turn touches multiple)
  | :irreversible    reason   (Undo button disabled, with explanation)
```

Irreversible actions still produce a receipt; the Undo button is just
greyed out and the row says why ("receipts committed cannot be undone here;
edit the cost entry from /receipts").

## 4. Lifecycle

### 4.1 Producing a receipt

A tool call that mutates state must:

1. Capture **before-state** sufficient to reverse the change.
2. Apply the mutation.
3. Return `{:ok, %DiffRow{}, %UndoHandle{}}` to the Router instead of the
   current ad-hoc prose+bubble shape.

The Router accumulates DiffRows + UndoHandles across the turn and, on
turn end (next assistant message), persists a single RunReceipt with the
composite UndoHandle.

### 4.2 Rendering

CaptureLive subscribes to the receipt for the active correlation_id. On
arrival, it renders a RunReceipt bubble (UI_SPEC §7.1) with:
- intent line
- grouped diff rows (by surface)
- assumptions block (if any)
- Undo button (disabled if `undo_handle == :irreversible`)

After Undo, the bubble re-renders with `reverted_at` set ("Reverted — Apply again?").

### 4.3 Undoing

`Tore.RunReceipts.undo(receipt_id, user_id)`:
1. Loads receipt, checks `reverted_at` is nil and `undo_expires_at` not passed.
2. Walks the UndoHandle and reverses each piece.
   - Event-sourced: append compensating events.
   - Snapshot: restore before_attrs.
3. Sets `reverted_at`.
4. Emits a follow-up RunReceipt for the undo itself (so the trail is honest).

### 4.4 Expiration

Undo handles have a default TTL (proposal: **24 hours** for low-blast-radius
mutations, **forever** for high-stakes ones like receipt commits — but those
are `:irreversible` here anyway). After expiry, the receipt persists for
audit but Undo is disabled.

## 5. Belief state on PantryItem

UI_SPEC §16.5 requires belief vocabulary. Add to `Tore.Pantry.PantryItem`:

```
belief          enum   (:confirmed, :probable, :uncertain, :missing)
last_seen_at    datetime
provenance      enum   (:manual, :receipt, :shelf_photo, :inferred)
```

`belief` is set by:
- `:manual` add → `:confirmed`
- receipt commit → `:probable` (we know it was bought, not that it's still there)
- shelf photo → `:confirmed`
- inference (agent guess based on similar recipes) → `:uncertain`
- agent `remove_from_pantry` → `:missing` (don't delete; mark missing)

The current schema is largely boolean. Migration plan in §8.

## 6. Lock on plan slots

UI_SPEC §16.6 requires user locks to outrank the agent. Add to the
plan-slot event stream:

```
PlanSlotLocked   { date, slot_key, locked_by_user_id, at }
PlanSlotUnlocked { date, slot_key, at }
```

State projection on Planning aggregate carries `locked_slots :: MapSet`.
Tools that mutate plan slots (`set_plan_slot`, `clear_plan_slot`, agent
suggestions) must check the projection:

- `set_plan_slot` with `force?: false` on a locked slot returns
  `{:error, :slot_locked}`. The agent surfaces this in the receipt:
  "Tore left Friday unchanged because it is locked by you."
- The user can explicitly unlock via UI.

`pin_plan_slot` (existing tool) becomes the agent-facing way to *request*
a lock; the actual lock event records `locked_by_user_id` of the active user.

## 7. Tool classification

Every agent tool gets classified for receipt production:

```
:silent      no receipt, no diff row
             (read-only tools: find_recipe, check_pantry, list_shopping_list)

:diff_row    produces a DiffRow that joins the turn's receipt
             (set_plan_slot, add_to_shopping_list, add_to_pantry, etc.)

:own_receipt produces its own RunReceipt, separate from the turn
             (receipt_commit, recipe_import — these are big enough that
             collapsing them into a chat turn's receipt would hide them)
```

Concrete classification of current `Tore.Capture.Dispatch` tools:

| Tool | Class | Undo |
|---|---|---|
| find_recipe | :silent | n/a |
| set_plan_slot | :diff_row | event-sourced |
| clear_plan_slot | :diff_row | event-sourced |
| suggest_meals_from_pantry | :silent | n/a (advisory) |
| add_to_shopping_list | :diff_row | event-sourced |
| check_off_shopping_item | :diff_row | event-sourced |
| list_shopping_list | :silent | n/a |
| generate_shopping_list_from_plan | :diff_row | event-sourced (batch) |
| add_to_pantry | :diff_row | snapshot |
| remove_from_pantry | :diff_row | snapshot |
| check_pantry | :silent | n/a |
| mark_recipe_cooked | :diff_row | snapshot |
| set_plan_servings | :diff_row | event-sourced |
| pin_plan_slot | :diff_row | event-sourced |
| skip_plan_meal | :diff_row | event-sourced |
| ingest_receipt | :own_receipt | :irreversible |
| update_pantry_from_shelf | :own_receipt | snapshot batch |

## 8. Phases

Implement in checkpoints, one commit per phase, each independently shippable.

### Phase 1 — Schema + module skeleton

Scaffolds `lib/tore/harness/` as the home of the future KitchenRun harness
(see Relationship section above). Run receipts are its first occupant.

- Migration: `run_receipts` and `run_receipt_diffs` tables.
- Migration: `pantry_items.belief`, `pantry_items.last_seen_at`,
  `pantry_items.provenance`.
- Migration: plan-slot lock events (new event types, no schema change since
  Planning is event-sourced).
- Module: `Tore.Harness.RunReceipt` — Ecto schema.
- Module: `Tore.Harness.RunReceiptDiff` — Ecto schema (the persisted form
  of DiffRow).
- Module: `Tore.Harness.UndoHandle` — sum-type encoding + serialiser.
- Module: `Tore.Harness.RunReceipts` — context with `record/1`, `get/1`,
  `list_for_household/2`, `undo/2`.
- No behavior change yet; just the substrate.

### Phase 2 — Router emits receipts for diff_row tools

- Refactor `Tore.Capture.Dispatch.dispatch_one/3` to return
  `{:ok, diff_row, undo_handle}` instead of a bubble.
- `Tore.Capture.Router` accumulates per-turn DiffRows and persists one
  RunReceipt at turn end.
- CaptureLive renders RunReceipt bubbles with Undo button (no-op wired yet).
- Existing `shop_link` bubble becomes the rendering of a shop-surface
  DiffRow group; same component, fed by the receipt.

### Phase 3 — Undo wired

- `Tore.RunReceipts.undo/2` actually reverses event-sourced and snapshot
  handles.
- CaptureLive Undo button calls it and shows the "Reverted" state.
- Toast on Plan/Shop when an Undo affecting that surface lands (PubSub).

### Phase 4 — Belief state on Pantry

- Backfill `belief` from existing `provenance` field where possible.
- `Pantry.upsert_belief/1` sets `belief` based on provenance.
- Shop list rendering checks pantry belief for items in
  `:probable`/`:confirmed` state and renders the `?` prefix with copy.
- Pantry list groups by belief, not just category.

### Phase 5 — Locks

- New plan-slot events and projection.
- Tools check `locked_slots` projection; emit `:slot_locked` diff row
  ("Tore left Friday unchanged — locked by you") when refusing.
- UI: lock toggle on plan slot card (Phase 5 of UI rebuild, separate spec).

### Phase 6 — Own-receipt flows + irreversible labelling

- `:irreversible` receipts for receipt commits with explanation copy.
- Recipe import becomes `:own_receipt` with a snapshot UndoHandle.

## 9. Non-goals

- **No Needs-Review inbox** in this spec. The agent-acts-immediately model
  makes it unnecessary for the common path. Defer until evidence shows
  certain mutations need a stage step.
- **No proposal/apply approval flow.** Same reason.
- **No multi-user concurrent-edit conflict resolution** beyond what
  event-sourced contexts already give us. If two users mutate the same
  slot in the same second, last write wins; the loser's RunReceipt still
  shows what they did and Undo restores their version.
- **No cross-household receipts.** Receipts are household-scoped.

## 10. Open questions

- **Q1.** Should `:irreversible` tools (receipt_commit) get a confirmation
  step in Capture before applying, given Undo can't help? Default answer:
  no — they already have their own review card. Keep the doctrine pure.
- **Q2.** Undo TTL — 24h is a guess. Revisit after Phase 3 ships and we
  see how often Undo gets used past the same-session window.
- **Q3.** Should run receipts surface in Today / Plan / Shop as small
  "Tore changed this 5 min ago — Undo" footers, not just in Capture?
  Probably yes (UI_SPEC §16.3.2 implies it). Decide when building the
  UI for those surfaces.

## 11. Decision log

- **2026-06-24:** Chose agent-acts-immediately over proposal-approval.
  Trust through visibility + reversibility, not friction. Doctrine
  appended to UI_SPEC §16 reflects this.
- **2026-06-24:** Named the artifact `RunReceipt` (matches UI_SPEC §7.1
  vocabulary) instead of `Proposal`. The earlier draft used `Proposal`
  but that implied an approval gate we're not building.
- **2026-06-27:** Reconciled with SPEC.md §Agent Harness. This spec is a
  vertical slice of the KitchenRun harness, not a parallel track.
  Phase 1 modules land under `lib/tore/harness/` (per SPEC.md §Module
  Map), so subsequent harness phases (capsules, verifiers, resolvers)
  extend the same directory rather than building beside it. Capsules,
  verifiers, resolver handles, formal risk tiers, and model routing
  are explicitly deferred to later phases — listed in the Relationship
  section.
