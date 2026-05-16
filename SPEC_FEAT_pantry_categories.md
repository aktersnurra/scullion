# Feature Spec: Pantry Categories

## Goal

Structure pantry items into a fixed set of categories, group them visually in the pantry UI, and enable cost tracking per category on grocery receipts.

---

## Category Enum

Defined as module attributes in `PantryItem`. One category per item. The LLM photo-scan prompt maps parsed items to these values; unrecognised values fall back to `other`.

| Atom            | Display (EN)      | Display (SV)        |
|-----------------|-------------------|---------------------|
| `dairy`         | Dairy             | Mejeri              |
| `meat`          | Meat & fish       | Kött & fisk         |
| `produce`       | Produce           | Frukt & grönt       |
| `frozen`        | Frozen            | Fryst               |
| `dry_goods`     | Dry goods         | Torrvaror           |
| `canned`        | Canned & jarred   | Konserver           |
| `herbs_spices`  | Herbs & spices    | Kryddor & örter     |
| `condiments`    | Condiments        | Såser & oljor       |
| `other`         | Other             | Övrigt              |

Category order in the UI follows the table order above.

---

## Schema Changes

- `pantry_items.category` stays a `:string` column (no migration needed).
- `PantryItem.changeset/2` adds `validate_inclusion(:category, categories())` where `categories()` returns the string list of atoms above.
- A new `PantryItem.categories/0` public function returns the ordered list of `{atom, display_string}` pairs for use in dropdowns and grouping.

---

## Pantry Context (`Tore.Pantry`)

- `list_inventory/0` returns items ordered by category (enum order) then by name within each category.
- New `list_inventory_grouped/0` returns `[{category_atom | nil, [PantryItem.t()]}]` — `nil` bucket last for uncategorised items.

---

## Pantry LiveView (`ToreWeb.PantryLive`)

- Replace free-text category `<input>` with a `<select>` dropdown in the add form and in the scan preview editor.
- Render items grouped under bold section headers (category display name) matching the reference UI style.
- Items without a category render under an "Other" section at the bottom.

---

## LLM Prompt (`priv/llm/prompts/parse_pantry_image.eex`)

- Add a line instructing the model to set `category` to one of the fixed enum values (English atom strings). Fallback to `"other"` if unsure.

---

## Cost Tracking (future hook — out of scope for this feature)

`LineItem` already has no category field. Category-level cost analysis will be a separate feature that joins pantry categories to grocery line items via ingredient name matching. This feature does not touch `Costs`.

---

## Out of Scope

- Multi-category per item
- DB-level CHECK constraint (not worth a migration for SQLite)
- Cost tracking integration (separate feature)
