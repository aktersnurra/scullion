# PLAN — UI Redesign

Implementation order. Each checkpoint is a commit. Stop and verify after
each.

## Checkpoint 1 — Tokens & CSS cleanup

**File**: `assets/css/app.css`

- Remove both `@plugin "../vendor/daisyui-theme"` blocks (dark + light).
- Remove `@custom-variant dark (...)`.
- Add `:root` block with all tokens from SPEC (colors, radii, spacing
  vars optional, type scale via `--t-*`).
- Keep tailwindcss + heroicons + daisyui plugin import (daisyui is used
  by some existing components; removing it is out of scope).
- Add base typography: `body { font: 16px/1.5 system-ui, ...; color:
  var(--text); background: var(--bg); }`.

**Verify**: `mix assets.build` succeeds. Open any page in browser — text
should still render, no dark theme available.

## Checkpoint 2 — Layout chrome

**File**: `lib/scullion_web/components/layouts.ex`

- Rewrite `def app/1`:
  - Top bar: white `var(--surface)`, 56px, hairline border-bottom
    `var(--border)`. Wordmark left, nav centered, user area right.
  - Nav items: Week (`/`), Groceries (`/groceries`), Prep (`/prep`),
    Pantry (`/pantry`), Costs (`/costs`), Settings (`/settings`).
    Hidden below `md`.
  - Active state via `@current_path` assign — green text + 2px green
    underline. Read path from `socket.assigns[:current_path]` if
    available, fall back to no active item (don't crash).
  - Mobile bottom nav: fixed bottom, white, hairline top border, 6
    columns, icon (heroicon) + 11px label, 56px tall.
  - `<main>` gets `padding: 24px` desktop, `16px` mobile, with
    `padding-bottom: 80px` on mobile to clear bottom nav.
- Delete `def theme_toggle/1` entirely.
- Keep `flash_group/1` and `flash/1` working — restyle minimally
  (rounded-md, var(--surface), var(--border), no shadows).

**Files to touch for `current_path`** (optional, low-effort):
`lib/scullion_web/router.ex` — add a `:put_current_path` plug or use
`live_session` `on_mount` to assign `current_path`. If this turns into
yak-shaving, skip and ship without active-state highlighting in this
checkpoint.

**Verify**: `mix compile --warnings-as-errors`. Visit `/`, `/groceries`,
`/recipes`. Header renders, links work, no console errors. Mobile
viewport (DevTools) shows bottom nav.

## Checkpoint 3 — Component primitives

**File**: `lib/scullion_web/components/core_components.ex`

Add these as new function components. Don't delete existing helpers
(`flash`, `button`, `input`, `error`, `header`, `table`, `list`, `icon`)
— they are referenced from generated code. Mark legacy ones with
`@doc deprecated:` later if needed.

Order to write (each ~15–40 lines):

1. `<.page>` — slot inner_block, max-w-3xl mx-auto wrapper. Optional
   `max_width` attr (`:sm | :md | :lg | :xl`).
2. `<.page_header>` — attrs: `title`, `subtitle` (optional), slot
   `actions` (right-aligned). Display type, 32px.
3. `<.section>` — attr `title` (optional), slot inner_block. h2 micro
   label + content.
4. `<.row>` — slots: `leading` (optional, image), `inner_block` (label),
   `trailing` (optional). 56px min-height, hairline bottom border, hover
   bg `var(--accent-soft)` if `clickable` attr is true.
5. `<.button>` — attrs: `variant` (`:primary | :ghost | :danger`,
   default `:primary`), `size` (`:md | :lg`, default `:md`), `type`
   (default `"button"`), passthrough rest. Primary = filled green,
   ghost = transparent green text, danger = red text.
6. `<.icon_button>` — square 44px, attrs: `icon` (heroicon name),
   `label` (sr-only).
7. `<.input>` — underline style. Attrs mirror Phoenix scaffold
   (`field`, `type`, `label`, `errors`).  Don't break form_for users.
   This is a NEW name; old `<.input>` stays.
   - Rename collision: define this as `<.field>` instead of `<.input>`
     to avoid clashing with the Phoenix-generated `<.input>` already in
     this module.
8. `<.checkbox>` — square 24px, label slot. Green fill + white check
   when checked.
9. `<.chip>` — attr `tone` (`:neutral | :accent | :muted`), text slot.
   Pill, 12px, padding 4/10.
10. `<.empty>` — attr `message`, single muted line, 32px vertical pad.
11. `<.drawer>` — slot `inner_block`, attrs: `id`, `show` (boolean),
    `on_close` (JS). Right-side slide-over, 100% h, max-w 420px,
    backdrop. Use `phx-mounted` / `JS.show/hide` for transitions.

For each component: add a one-line `@doc` with a usage example. No
multi-paragraph docstrings.

**Verify**: `mix compile --warnings-as-errors`. Components don't need to
be wired into screens yet.

## Checkpoint 4 — UI.md update

**File**: `UI.md`

Replace the dark-mode palette section + navigation section to match the
chosen direction. Keep the screen sketches (planner, grocery, prep,
etc.) — they're still useful. Single edit pass, ~20 lines changed.

Specifically:
- Palette → light tokens from SPEC.
- Navigation → top bar (kiosk) / bottom bar (mobile), no sidebar
  language.
- Component primitives section → reference the 11 new primitives by
  name.
- Drop the "next step" CTA at the bottom (this *is* the next step).

## Checkpoint 5 — Verification & polish

- Run `mix compile --warnings-as-errors`.
- Run `mix test`.
- Start the server: `mix phx.server`. Smoke-test:
  - `/login` (still works, will look unstyled inside — fine)
  - `/` planner (header + bottom nav render, content unstyled — fine)
  - `/groceries` (same)
  - Resize to mobile width — bottom nav visible, top nav hidden, content
    not obscured.
- Commit.

If any existing test asserts on a removed Tailwind class
(`text-gray-600` etc.), fix the test by asserting on text content
instead. If any test asserts on theme-toggle markup, delete that
assertion.

## Out of scope (next session)

- Per-screen redesigns (Planner, Grocery, Recipe, Login, Pantry, Costs,
  Prep, Settings).
- Recipe imagery wiring (mocks show food photos — that's Recipe screen
  work).
- Drawer animation polish beyond a basic show/hide.
