# Phase 8 — Pantry & Polish

## Overview

Wire up the Pantry context (migration + schema + CRUD), integrate it with the Groceries
handler (checked-off items auto-add to pantry), add nutritional estimates via LLM, and
add plain-text grocery list export for SMS.

### What exists (stubs / skeleton)

- `lib/scullion/pantry.ex` — `add_item/1`, `remove_item/1`, `list_inventory/0` all stub
- `lib/scullion/pantry/pantry_item.ex` — schema exists, bare `ingredient_id` integer field,
  no changeset, no `belongs_to`
- `lib/scullion_web/live/pantry_live.ex` — renders `<div>Pantry</div>`
- `test/scullion/pantry_test.exs` — empty DataCase shell
- `lib/scullion/llm.ex` — no `estimate_nutrition/1` callback yet
- `lib/scullion/handlers/groceries_handler.ex` — `check_item/3` exists but does not call Pantry

### What is missing

- Migration: `pantry_items` table (no migration exists)
- Changeset on `PantryItem`, proper `belongs_to :ingredient` (optional)
- `Pantry` public API implementation
- Grocery → Pantry integration: `check_item/3` in GroceriesHandler calls `Pantry.add_item/1`
- LLM behaviour: `estimate_nutrition/1` callback
- OpenRouter adapter: `estimate_nutrition/1` implementation + prompt template
- Nutritional estimates display on recipe LiveView (or pantry LiveView)
- Grocery list plain-text export: `GroceriesHandler.export_list/1` → formatted string
- `PantryLive` implementation
- Tests: `pantry_test.exs`, `groceries_handler_test.exs` additions, `pantry_live_test.exs`

---

## Migration

### `20260504000013_create_pantry_items.exs`

```elixir
create table(:pantry_items) do
  add :name, :string, null: false
  add :quantity, :decimal
  add :unit, :string
  add :category, :string
  add :ingredient_id, references(:ingredients, on_delete: :nilify_all)
  add :added_at, :date, null: false
  add :expires_at, :date
  timestamps()
end

create index(:pantry_items, [:ingredient_id])
```

Note: `added_at` and `expires_at` are `:date` not `:utc_datetime` — the schema stores day
precision. The existing schema has `:utc_datetime`; the migration will use `:date` and the
schema field type will be corrected to match.

---

## Schemas

### `lib/scullion/pantry/pantry_item.ex`

- Change `field :ingredient_id, :integer` → `belongs_to :ingredient, Scullion.Recipes.Ingredient`
- Change `field :added_at, :utc_datetime` → `field :added_at, :date`
- Change `field :expires_at, :utc_datetime` → `field :expires_at, :date`
- Add `import Ecto.Changeset` and `changeset/2` validating `:name, :added_at`

---

## `lib/scullion/pantry.ex`

Implement three functions:

### `add_item/1`

Accepts `%{name, quantity, unit, category, ingredient_id, added_at, expires_at}`.
`added_at` defaults to `Date.utc_today()` if not provided.

```elixir
def add_item(attrs) do
  attrs = Map.put_new(attrs, :added_at, Date.utc_today())
  %PantryItem{} |> PantryItem.changeset(attrs) |> Repo.insert()
end
```

### `remove_item/1`

Accepts `item_id :: integer()`. Deletes by primary key.

```elixir
def remove_item(item_id) do
  case Repo.get(PantryItem, item_id) do
    nil -> {:error, :not_found}
    item -> Repo.delete(item) |> then(fn _ -> :ok end)
  end
end
```

### `list_inventory/0`

Returns all pantry items ordered by name.

```elixir
def list_inventory do
  Repo.all(from p in PantryItem, order_by: p.name)
end
```

---

## Grocery → Pantry Integration

### `lib/scullion/handlers/groceries_handler.ex` — `check_item/3`

After a successful `CheckItem` event, look up the item from the resulting state and call
`Pantry.add_item/1`. The item name and unit come from the grocery state (held in EventStore).

The `run/2` private helper returns `{:ok, events}` — we need the post-check state to read
item details. Change `check_item/3` to call Pantry after appending:

```elixir
def check_item(list_id, item_id, user_id) do
  with {:ok, state} <- EventStore.load(list_id, Decider),
       {:ok, events} <- Decider.decide(%Commands.CheckItem{item_id: item_id, checked_by: user_id}, state),
       :ok <- EventStore.append(list_id, events) do
    PubSub.broadcast(@pubsub, @topic, {:events, events})
    item = Map.get(state.items, item_id)
    if item, do: Pantry.add_item(%{name: item.name, quantity: item.quantity, unit: item.unit})
    {:ok, events}
  end
end
```

`Pantry.add_item/1` failure is fire-and-forget — it does not affect the check_item result.
This preserves the decider's integrity (grocery state is consistent regardless of pantry).

---

## LLM: Nutritional Estimates

### `lib/scullion/llm.ex`

Add callback:

```elixir
@callback estimate_nutrition(recipe :: map()) :: {:ok, map(), map()} | {:error, term()}
```

### `priv/llm/prompts/estimate_nutrition.eex`

Static prompt instructing the model to return rough macros as JSON:

```
System: You are a nutritionist. Given a recipe name and key ingredients, estimate
macronutrients per serving. Return JSON only:
{"calories": 450, "protein_g": 30, "carbs_g": 40, "fat_g": 15, "notes": "..."}
These are rough estimates, not medical advice.
```

### `lib/scullion/llm/prompts.ex` — add `estimate_nutrition/0`

```elixir
def estimate_nutrition do
  system = File.read!(Path.join(@prompts_dir, "estimate_nutrition.eex"))
  {system, ""}
end
```

The user message will be assembled in the adapter from the recipe map.

### `lib/scullion/adapters/open_router.ex` — implement `estimate_nutrition/1`

```elixir
def estimate_nutrition(%{title: title, ingredients: ingredients}) do
  {system, _} = Scullion.LLM.Prompts.estimate_nutrition()
  user = "Recipe: #{title}\nIngredients: #{Enum.join(ingredients, ", ")}"
  chat(system, user)
end
```

Returns `{:ok, %{"calories" => _, "protein_g" => _, ...}, usage}`.

---

## Grocery List Export

### `lib/scullion/handlers/groceries_handler.ex` — add `export_list/1`

Accepts `list_id`. Loads current state, formats items as plain text grouped by checked status.

```elixir
def export_list(list_id) do
  with {:ok, state} <- EventStore.load(list_id, Decider) do
    lines =
      state.items
      |> Map.values()
      |> Enum.reject(& &1.checked)
      |> Enum.sort_by(& &1.name)
      |> Enum.map(fn item ->
        qty = if item.quantity, do: "#{item.quantity} #{item.unit} ", else: ""
        "- #{qty}#{item.name}"
      end)

    {:ok, Enum.join(lines, "\n")}
  end
end
```

Only unchecked items are exported (already-bought items are excluded).

---

## `lib/scullion_web/live/pantry_live.ex`

Two-panel view: inventory list + add-item form.

### `mount/3`

Load `Pantry.list_inventory()`. Assign `items: items`.

### Handles

- `"add_item"` — form submit `{name, quantity, unit, category, expires_at}` → `Pantry.add_item/1`; reload inventory
- `"remove_item"` — `%{"id" => id}` → `Pantry.remove_item/1`; reload inventory

### Render

Display items in a table: name, quantity + unit, category, expires_at (with expiry warning
if ≤ 3 days away). Add-item form for member/admin. Remove button per row (member/admin only).

---

## Tests

### `test/scullion/pantry_test.exs`

Use `async: false`, DataCase sandbox. Tests:

1. `add_item/1` inserts and returns pantry item
2. `add_item/1` defaults `added_at` to today when omitted
3. `add_item/1` returns error on missing `:name`
4. `remove_item/1` deletes existing item, returns `:ok`
5. `remove_item/1` returns `{:error, :not_found}` for unknown id
6. `list_inventory/0` returns all items ordered by name

### `test/scullion/handlers/groceries_handler_test.exs`

Add one test to the existing groceries handler tests (if file exists) or create new file:

1. `check_item/3` calls `Pantry.add_item/1` with item name/quantity/unit after check

Use Mox if Pantry is behind a behaviour — but Pantry is a plain context (not a port), so
the test uses the real Pantry with a sandbox checkout and asserts a `PantryItem` was inserted.

### `test/scullion_web/live/pantry_live_test.exs`

Use `ConnCase`. Tests:

1. Mount renders inventory (empty state shows "Nothing in pantry")
2. Add item via form → item appears in list
3. Remove item → item removed from list

---

## Implementation Order

1. Migration: `create_pantry_items` — run `mix ecto.migrate`
2. Update `pantry_item.ex` — fix field types, add `belongs_to`, add `changeset/2`
3. Implement `Pantry.add_item/1`, `remove_item/1`, `list_inventory/0`
4. Wire `check_item/3` in GroceriesHandler to call `Pantry.add_item/1`
5. Add `estimate_nutrition/1` callback to `Scullion.LLM`; add stub to OpenRouter adapter
6. Write `priv/llm/prompts/estimate_nutrition.eex`; implement adapter
7. Add `export_list/1` to GroceriesHandler
8. Implement `PantryLive`
9. Tests: pantry_test.exs, groceries_handler additions, pantry_live_test.exs
10. `mix compile --warnings-as-errors && mix test`

---

## Constraints & Decisions

- **`Pantry.add_item/1` after check_item is fire-and-forget.** Pantry is best-effort.
  The grocery event store is the source of truth for the list; pantry is a secondary side effect.
  A failed pantry insert does not roll back the check event.
- **`added_at` / `expires_at` are `:date` not `:utc_datetime`.** The existing schema has
  `:utc_datetime` — this is a bug in the stub. The migration and schema will use `:date`.
- **No pantry migration existed.** The `pantry_items` table was never created. Migration
  timestamp: `20260504000013`.
- **Nutrition estimates are display-only.** No new schema. The LLM result is shown in the
  UI (recipe detail or pantry) but not persisted. Keep it simple.
- **Export is plain text, no new LiveView.** A button in `grocery_live.ex` calls
  `GroceriesHandler.export_list/1` and renders the result in a `<pre>` tag or textarea for
  copy-paste. No new route needed.
- **`ingredient_id` FK is optional.** Most pantry items added from grocery check-off will
  not have an `ingredient_id` (the grocery item carries only name/quantity/unit). The FK
  is nullable.
- **MockLLM already covers `estimate_nutrition/1`** once the callback is added — Mox
  auto-mocks all callbacks declared in the behaviour. No extra setup needed.
