# Plan: Pantry Categories

## Checkpoints

### 1 — PantryItem enum + validation
- Add `@categories` ordered list to `PantryItem` as `{atom, display}` pairs
- Expose `PantryItem.categories/0` public function
- Add `validate_inclusion(:category, ...)` to `changeset/2`
- Files: `lib/tore/pantry/pantry_item.ex`
- Verify: `mix test test/tore/pantry_test.exs`

### 2 — Pantry context grouping
- Update `list_inventory/0` to order by category enum position then name
- Add `list_inventory_grouped/0` returning `[{category | nil, [item]}]`
- Files: `lib/tore/pantry.ex`
- Verify: `mix test test/tore/pantry_test.exs`

### 3 — LLM prompt update
- Add category constraint instruction to `parse_pantry_image.eex`
- Files: `priv/llm/prompts/parse_pantry_image.eex`
- Verify: manual review of prompt text

### 4 — LiveView UI
- Switch add form category input to `<select>` using `PantryItem.categories/0`
- Switch scan preview category input to `<select>`
- Render inventory grouped under bold section headers using `list_inventory_grouped/0`
- Files: `lib/tore_web/live/pantry_live.ex`
- Verify: `mix test test/tore_web/live/pantry_live_test.exs`, visual check in browser

## Interface Notes

- `PantryItem.categories/0` → `[{atom(), String.t()}]` e.g. `[{:dairy, "Dairy"}, ...]`
- `Pantry.list_inventory_grouped/0` → `[{atom() | nil, [PantryItem.t()]}]`
- Category order is fixed by `@categories` list position, not alphabetical
