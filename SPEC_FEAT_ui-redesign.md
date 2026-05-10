# SPEC — UI Redesign

## Why

Current UI is incoherent: hardcoded Tailwind grays, card-on-card layouts,
inconsistent radii and spacing, tap targets too small for kiosk, every
LiveView reinvents primitives. UI.md, the home-page mock, and the
weekly-view mock describe three different design languages.

## Direction (chosen)

Light theme, no sidebar, full-bleed list rows with imagery, green accent —
the **weekly-view-mock / draft-ui** style. Top horizontal nav (kiosk),
sticky bottom nav (mobile). Dark mode out of scope.

UI.md is updated to match this direction so it stops contradicting the
mocks.

## Design tokens

- **Colors** (CSS vars on `:root`):
  - `--bg`: #fafafa (page)
  - `--surface`: #ffffff (rows, drawers)
  - `--text`: #111827
  - `--muted`: #6b7280
  - `--subtle`: #9ca3af
  - `--border`: #f3f4f6 (hairlines only)
  - `--accent`: #16a34a (green-600 — checked / today / primary CTA)
  - `--accent-hover`: #15803d
  - `--accent-soft`: #dcfce7 (chips, soft fills)
  - `--danger`: #dc2626 (rare, destructive only)
- **Radii**: `--r-sm` 8px, `--r-md` 12px, `--r-lg` 16px, `--r-pill` 9999px.
  Pick one per element class — no mixing.
- **Spacing**: 8px grid. Allowed: 4, 8, 12, 16, 20, 24, 32, 48.
- **Type scale**:
  - `--t-display` 32px / 600 — page hero (recipe title, day label)
  - `--t-h1` 24px / 600 — section titles
  - `--t-h2` 18px / 600 — row titles
  - `--t-body` 16px / 400 — body, list rows
  - `--t-meta` 14px / 400 — secondary metadata
  - `--t-micro` 12px / 500 uppercase — labels (MON, TUE)
- **Tap targets**: minimum 44px height. Primary CTAs 48–56px.

Tokens live in `assets/css/app.css` as `:root` vars and are consumed by
Tailwind utilities (`bg-[var(--surface)]`) or component classes. No
hardcoded `text-gray-*` / `bg-gray-*` in HEEx.

## Component primitives (in `core_components.ex`)

Replace the Phoenix scaffold helpers. Build:

1. `<.page>` — outer container (max-width, padding, page background)
2. `<.page_header>` — title + optional CTA + optional subtitle/stepper
3. `<.section>` — titled block, no inner card
4. `<.row>` — flat list row (label / value / trailing slot, leading image
   slot for recipes). Tap-target safe.
5. `<.button variant={:primary | :ghost | :danger} size={:md | :lg}>`
6. `<.icon_button>` — square 44px, used for nav arrows, close, etc.
7. `<.input>` — underline style, not boxed
8. `<.checkbox>` — square, large (24px), green when checked
9. `<.chip>` — pill for counts, "Leftovers", "Today"
10. `<.empty>` — single-line muted text, no illustrations
11. `<.drawer>` — right-side slide-over for swap/edit flows

Old `core_components.ex` helpers (`.flash`, `.button`, `.input`, etc.) are
rewritten — not deleted — so existing screens keep compiling during the
migration.

## Layout chrome

- `layouts.ex :app` rewritten:
  - Top bar: 56px, white, hairline bottom border. Wordmark left, nav
    centered (Week · Groceries · Prep · Pantry · Costs · Settings),
    user/logout on the right.
  - Mobile (< md): hide top nav, render fixed bottom nav with the same
    items as 44px icon+label tiles.
- Active nav item: green underline + green text. No hover background
  noise.
- `<main>` background `var(--bg)`, content padding `24px` desktop / `16px`
  mobile.
- Theme toggle and dark theme block deleted from app.css and layouts.ex.

## What this session does NOT do

- Does not rewrite Planner / Grocery / Recipe screens. Those follow in
  later sessions, one at a time, on top of the new primitives.
- Does not add tests. Visual change only; existing LiveView tests must
  continue to pass (asserting on text content, not classes).

## Done means

- `mix compile --warnings-as-errors` clean.
- `mix test` green (existing tests still pass).
- `assets/css/app.css` has tokens, no daisyUI dark theme.
- `core_components.ex` exports the new primitives with `@doc` examples.
- `layouts.ex :app` renders the new chrome on every existing screen
  without breaking layout (screens may look unstyled inside — expected;
  per-screen redesigns come next).
- UI.md updated to match the chosen direction.
