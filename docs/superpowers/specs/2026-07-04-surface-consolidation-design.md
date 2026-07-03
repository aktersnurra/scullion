# Surface consolidation — layers, not pages

> Design delta against `UI_SPEC.md` (2026-07-04). Approved decisions from the
> 2026-07-03/04 design discussion. This document changes navigation shape,
> receipt placement, and three surface compositions. It does not change the
> visual system (UI_SPEC §4), the component system (§5), or the harness
> contract (SPEC.md §A) except where §A.9 requires new artifact fields.

## Goal

Fewer destinations, zero archaeology. Screens map to moments in the food
loop, not to data types. Detail arrives as layers (sheets that expand in
place) instead of pages you navigate to and back from. Maximum depth from
any nav destination: two (surface → sheet).

## Decisions recorded

| Decision | Choice |
|---|---|
| Photo routing in Capture | Keep LLM classification (`classify_image`); explicit intent chips considered and rejected |
| Receipts & reviews | Layered: inline strips + expand-in-place sheets + one review pill on Today; full audit list in Settings; no inbox page in nav |
| Week strip on Today | Cut. The whole week is viewed on Plan, one tap away |
| Deals | Suggestions-only, no browsing surface; deal-linked items must carry exact product identity (brand, size, price, store) |
| Shop grouping | Store sections (already UI_SPEC §6.3 default; confirmed) |
| Navigation | Three tabs (Today · Plan · Shop) + Capture as a global action, not a tab |

## 1. Navigation

**Delta to UI_SPEC §3.1–3.3.**

Mobile bottom nav goes from four tabs to three plus one action:

```
[Today]  [Plan]  [Shop]          (+ Capture FAB, all surfaces)
```

Capture is an action, not a destination (tabs are destinations; actions are
buttons). The FAB opens Capture as a full-screen sheet over whatever surface
you're on; dismissing it returns you exactly where you were. The redundancy
in current UI_SPEC (Capture tab *and* floating Capture/Ask button) resolves
in favor of the button.

Desktop left rail: Today / Plan / Shop, Capture as the rail's action button,
Settings at the bottom (unchanged).

Route map deltas:

```
/shop             (rename from /groceries — completes the Shop rename)
/capture          stays routable (deep links) but presents as a sheet
/settings         one page; /settings/memory|pantry|spending become anchors, not routes
/kiosk/capture    (rename from /kiosk/chat)
/prep             removed — prep renders inside Plan
inbox/run-review  never in nav; run detail stays routable for deep links, presents as a sheet
```

## 2. The layer doctrine

**Addition to UI_SPEC §4.8 (motion) and §5 (components).**

- The base surface never navigates away for detail. Detail expands in place
  (sheet or expanding card) and dismisses with a flick or scrim tap.
- Motion's only job is continuity: the element you tapped grows into the
  layer; the layer collapses back to it. 200–300 ms, standard curve.
  No decorative motion; respect reduced-motion (§11).
- Every hidden thing has a visible handle. A pill, a strip, a card edge —
  something you can see tells you where the layer lives. No mystery-meat
  gestures.
- LiveView mapping: layers are function components + `JS.transition`,
  driven by `live_patch` where deep-linkable, plain assigns where not.
  No new LiveView modules per layer.

## 3. Receipts and reviews, layered

**Delta to UI_SPEC §7.1 (placement/behavior; content unchanged) and to the
route map. Replaces `inbox_live` and `run_review_live` as destinations.**

- **Receipt strip.** When a run applies, a one-line receipt slides in at the
  bottom of the run's `surface` (the `KitchenRun.surface` field: Plan runs on
  Plan, grocery/pantry runs on Shop, capture ingestion in the Capture sheet).
  A run that changed multiple domains still gets one strip, on its starting
  surface; the expanded sheet shows all changed domains (UI_SPEC §7.1 already
  renders Plan + Shop sections in one receipt). If the user isn't on that
  surface when the run applies — scheduled runs especially — the receipt is
  simply unseen and reaches them through the review pill. Content per
  UI_SPEC §7.1: summary counts + `[Undo] [See changes]`.
- **Receipt sheet.** Tapping the strip expands it in place into the full
  receipt: diff rows (§16.4 alphabet), "Why this?", Undo. Flick down to
  dismiss. `run_review_live`'s content becomes this sheet.
- **Review pill.** Today carries one quiet pill — `2 to review` — rolling up
  unseen receipts and `:needs_user` runs across all surfaces. It expands
  into the same sheets. Not a red badge, not a count of unread anxiety:
  a calm handle, invisible when there is nothing to review.
- **Audit list.** Settings gains a **Run history** section: the full
  kitchen-runs table (SPEC.md success criterion 11) for the rare
  "what happened last month?" dig. Reachable, never surfaced.
- **Kiosk shows no receipts, pill, or reviews.** The kiosk shows the state
  of dinner, never the process of the system.

## 4. Today

**Delta to UI_SPEC §6.1.**

Composition, top to bottom:

```
Header      Today · date · avatar→Settings
Hero        Tonight card (unchanged, §6.1)
Secondary   Tomorrow compact card
            One counter note (max, unchanged)
            Review pill (only when something needs eyes)
Floating    Capture FAB
```

Removed: the week strip. Tomorrow answers "what's next"; the full week is
Plan's job, one tap away. Today's rules (§6.1) gain one line:

```
Today must not duplicate the week — that is Plan.
```

## 5. Plan

**Delta to UI_SPEC §6.2.**

- **Prep folds in.** The prep guide renders inside the week — an expandable
  prep layer anchored to the day it serves (Sunday prep on Sunday, etc.).
  `/prep` is removed as a destination; `prep_live` content becomes a sheet.
- **Recipes stay search-first.** Assigning a slot opens the recipe search
  sheet; recipe detail is a sheet from there. No recipe library in nav
  (already UI_SPEC doctrine; restated because prep/deals changes touch the
  same section).
- **Deals are suggestions only.** No deals rail, no deals browsing surface.
  Deals reach the user exactly three ways: the `UseTheDeals` skill chip, a
  `:deal_match` counter note, and per-slot rationale ("pork on sale at
  ICA"). `deals_live` is removed from user-facing routes.
- Receipt strips from plan runs appear here per §3 above.

## 6. Shop

**Delta to UI_SPEC §6.3 (small).**

- Grouping: store sections — confirmed as decided, no change to the §6.3
  group list.
- **Deal-linked rows carry exact product identity.** When an item is on the
  list because of a deal, the row names the actual product, not the generic
  ingredient:

  ```
  ☐ Feta
      Apetina 200 g · 25 kr · ICA
  ```

  Generic name stays primary (that's what you scan for in the aisle); the
  deal product line is tertiary weight. Rationale: multiple brands of the
  same ingredient exist; a deal is only real if you buy the right one.
- A receipt-photo entry point lives on Shop (camera affordance near the add
  input) — the store is where receipts happen. It opens the same Capture
  sheet pre-focused on the camera.

## 7. Settings

**Delta to UI_SPEC §6.7 and route map.**

One flat scrollable page, anchored sections, zero sub-pages:

```
Household preferences
Kitchen Memory
Pantry belief        (read-only "here's what we think you have")
Spending             (current cost_live content)
Run history          (audit list, §3 above)
Devices
Account
```

Section detail that needs interaction (e.g. a receipt in Spending, a run in
Run history) opens as a sheet. `/settings/memory`, `/settings/pantry`,
`/settings/spending` become in-page anchors.

## 8. Artifact-boundary implications (SPEC.md §A.9)

The UI needs fields the harness spec must name — per §A.9 that is a SPEC.md
amendment, listed here for the implementation plan:

1. **Deal product identity.** `DealsDigestCapsule` entries and any
   deal-attributed grocery item (in `GroceryDiff` / shop aggregate items)
   carry `product_label`, `package_size`, `price`, `store` — not just the
   ingredient name. Rationale strings citing a deal name the exact product.
2. **Receipt seen-state.** The review pill needs "unseen receipts" — runs
   carry a `seen_at`-style projection (likely on the run-receipts
   projection, not the aggregate). `:needs_user` runs are always unseen
   until answered or discarded.

No other harness changes: receipts, undo, diff rows, and the runs table all
exist; this design only moves where they render.

## 9. Out of scope

- Visual system changes (colors, type, shape — UI_SPEC §4 stands).
- Kiosk changes beyond the naming already in SPEC.md.
- Voice input, native apps, notifications (SPEC.md non-goals).
- Rebuilding surfaces not named here (Cooking mode unchanged).

## 10. Implementation order (for the plan)

1. Nav shell: 3 tabs + FAB; `/shop` rename; Capture as sheet.
2. Receipt strip + sheet components; wire to existing run_receipts
   projection; review pill on Today; remove inbox/run-review from nav.
3. Today: drop week strip, add pill.
4. Settings flattening (+ Run history section; fold Spending in).
5. Plan: prep layer; remove `/prep`, `/deals` from user routes.
6. Shop: deal product line (needs SPEC.md amendment #1 first).

Each step is independently shippable; UI_SPEC gets amended alongside the
step that changes it.
