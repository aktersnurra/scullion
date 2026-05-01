# Phase 1 Skeleton Plan

## Files to Create

### Infrastructure

| File | Notes |
|------|-------|
| `lib/scullion/event_store.ex` | Full implementation — append-only log, fold to state |
| `lib/scullion/llm.ex` | `@behaviour` with all 6 callbacks |
| `lib/scullion/http.ex` | `@behaviour` with `fetch/1` callback |
| `lib/scullion/scheduler.ex` | Placeholder module, Quantum wired in Phase 4 |

### Event-sourced aggregates

| File | Notes |
|------|-------|
| `lib/scullion/planning/commands.ex` | Defstructs: GeneratePlan, AssignRecipe, RemoveRecipe, SetServings, MarkLeftover |
| `lib/scullion/planning/events.ex` | Defstructs: PlanGenerated, RecipeAssigned, RecipeRemoved, ServingsChanged, LeftoverMarked |
| `lib/scullion/planning/state.ex` | `%State{week_start: nil, slots: %{}}` |
| `lib/scullion/planning/decider.ex` | `initial/0`, `decide/2`, `evolve/2` — all clauses stub-return empty |
| `lib/scullion/groceries/commands.ex` | Defstructs: BuildList, AddItem, RemoveItem, CheckItem, UncheckItem |
| `lib/scullion/groceries/events.ex` | Defstructs: ListBuilt, ItemAdded, ItemRemoved, ItemChecked, ItemUnchecked |
| `lib/scullion/groceries/state.ex` | `%State{week_start: nil, items: %{}}` |
| `lib/scullion/groceries/decider.ex` | `initial/0`, `decide/2`, `evolve/2` — all clauses stub-return empty |
| `lib/scullion/groceries/aggregator.ex` | `aggregate([Recipe]) :: [GroceryItem]` — returns `[]` stub |

### CRUD contexts — public API modules

| File | Notes |
|------|-------|
| `lib/scullion/accounts.ex` | Stub: create_user, authenticate, update_preferences, generate_device_token, revoke_device_token |
| `lib/scullion/recipes.ex` | Stub: create, update, list, search, get, scrape_from_url |
| `lib/scullion/deals.ex` | Stub: upsert_deals, list_current, clear_expired |
| `lib/scullion/pantry.ex` | Stub: add_item, remove_item, list_inventory |
| `lib/scullion/costs.ex` | Stub: log_receipt, log_dining_out, weekly_summary, monthly_summary, cost_per_meal |
| `lib/scullion/prep.ex` | Stub: save_guide, get_guide_for_week |

### CRUD contexts — Ecto schemas (compile-only; tables added in later phases)

| File | Notes |
|------|-------|
| `lib/scullion/accounts/user.ex` | schema "users": name, account_code_hash, role enum, preferences map |
| `lib/scullion/accounts/device_token.ex` | schema "device_tokens": token_hash, name, revoked_at |
| `lib/scullion/recipes/recipe.ex` | schema "recipes": title, description, instructions, base_servings, times, source_url, video_url, last_used_at, created_by |
| `lib/scullion/recipes/ingredient.ex` | schema "ingredients": name, category, default_unit |
| `lib/scullion/recipes/recipe_ingredient.ex` | schema "recipe_ingredients": recipe_id, ingredient_id, quantity, unit, notes |
| `lib/scullion/recipes/tag.ex` | schema "tags": name |
| `lib/scullion/recipes/parser.ex` | Pure: `parse_html(html) :: {:ok, map()} \| {:error, term()}` stub |
| `lib/scullion/deals/deal.ex` | schema "deals": store, store_location, product_name, brand, size, price, valid_from/until, source |
| `lib/scullion/deals/store_config.ex` | schema "store_configs": name, chain, store_id, url, scrape_enabled |
| `lib/scullion/deals/parsers/parser.ex` | `@behaviour` with `parse(html) :: {:ok, [map()]}` |
| `lib/scullion/deals/parsers/ica.ex` | `@behaviour Scullion.Deals.Parsers.Parser` stub |
| `lib/scullion/deals/parsers/coop.ex` | `@behaviour Scullion.Deals.Parsers.Parser` stub |
| `lib/scullion/pantry/pantry_item.ex` | schema "pantry_items": name, quantity, unit, category, ingredient_id, added_at, expires_at |
| `lib/scullion/costs/receipt.ex` | schema "receipts": date, store_name, total_amount, image_path, user_id |
| `lib/scullion/costs/line_item.ex` | schema "line_items": receipt_id, product_name, quantity, unit_price, total_price |
| `lib/scullion/costs/dining_out.ex` | schema "dining_out": date, description, total_amount, num_people, user_id |
| `lib/scullion/prep/prep_guide.ex` | schema "prep_guides": week_start, instructions, timeline (JSON) |

### Handlers (imperative shell)

| File | Notes |
|------|-------|
| `lib/scullion/handlers/planning_handler.ex` | Stub with function signatures matching spec |
| `lib/scullion/handlers/groceries_handler.ex` | Stub — `check_item/3` pattern from spec |
| `lib/scullion/handlers/recipe_handler.ex` | Stub |
| `lib/scullion/handlers/deals_handler.ex` | Stub |
| `lib/scullion/handlers/costs_handler.ex` | Stub |
| `lib/scullion/handlers/prep_handler.ex` | Stub |

### Adapters

| File | Notes |
|------|-------|
| `lib/scullion/adapters/open_router.ex` | `@behaviour Scullion.LLM` — all callbacks return `{:error, :not_implemented}` |
| `lib/scullion/adapters/req_http.ex` | `@behaviour Scullion.HTTP` — `fetch/1` returns `{:error, :not_implemented}` |

### Web layer

| File | Notes |
|------|-------|
| `lib/scullion_web/live/setup_live.ex` | `use ScullionWeb, :live_view` — minimal mount + render |
| `lib/scullion_web/live/login_live.ex` | Same |
| `lib/scullion_web/live/planner_live.ex` | Same |
| `lib/scullion_web/live/recipe_live.ex` | Same |
| `lib/scullion_web/live/grocery_live.ex` | Same |
| `lib/scullion_web/live/prep_live.ex` | Same |
| `lib/scullion_web/live/deals_live.ex` | Same |
| `lib/scullion_web/live/pantry_live.ex` | Same |
| `lib/scullion_web/live/cost_live.ex` | Same |
| `lib/scullion_web/live/settings_live.ex` | Same |
| `lib/scullion_web/plugs/auth.ex` | `init/1`, `call/2` — pass-through stubs |
| `lib/scullion_web/plugs/device_auth.ex` | Same |

### Migration

| File | Notes |
|------|-------|
| `priv/repo/migrations/20260501000001_create_events.exs` | Only migration for Phase 1 |

### Tests

| File | Notes |
|------|-------|
| `test/scullion/planning/decider_test.exs` | `async: true`, tests `initial/0` returns empty state |
| `test/scullion/groceries/decider_test.exs` | Same |
| `test/scullion/groceries/aggregator_test.exs` | Tests `aggregate([])` returns `[]` |
| `test/scullion/recipes/parser_test.exs` | Placeholder (no test body yet) |
| `test/scullion/deals/parsers/ica_test.exs` | Placeholder |
| `test/scullion/accounts_test.exs` | `use Scullion.DataCase` — placeholder |
| `test/scullion/costs_test.exs` | Same |
| `test/scullion/pantry_test.exs` | Same |

---

## EventStore Design

### Internal schema (`Scullion.EventStore.Event`)

Defined as a private Ecto schema nested inside `event_store.ex`. Not a separate file.

```
schema "events"
  :id          integer PK autoincrement
  :stream_id   :string  NOT NULL  — e.g. "grocery_list:2026-w18"
  :stream_type :string  NOT NULL  — "groceries" | "planning"
  :event_type  :string  NOT NULL  — short name, e.g. "ItemChecked"
  :data        :string  NOT NULL  — JSON payload
  :metadata    :string            — JSON (user_id, correlation_id)
  :inserted_at :naive_datetime NOT NULL
```

### `load/2`

```elixir
@spec load(stream_id :: String.t(), decider :: module()) :: {:ok, state}
```

1. Query `events` WHERE `stream_id = ^stream_id` ORDER BY `id ASC`
2. Derive events module from decider by replacing last segment: `Decider` → `Events`
   - e.g. `Scullion.Groceries.Decider` → `Scullion.Groceries.Events`
3. For each raw row, call `deserialize(events_module, event_type, data)`:
   - `module = Module.concat([events_module, event_type])`
   - `attrs = Jason.decode!(data, keys: :atoms)`
   - `struct!(module, attrs)`
4. `Enum.reduce(rows, decider.initial(), fn raw, acc -> decider.evolve(acc, event) end)`
5. Return `{:ok, state}`

### `append/2`

```elixir
@spec append(stream_id :: String.t(), events :: [struct()]) :: :ok | {:error, term()}
```

1. For each event struct, derive:
   - `stream_type`: `event.__struct__ |> Module.split() |> Enum.at(-3) |> String.downcase()`
     - `Scullion.Groceries.Events.ItemChecked` → `"groceries"`
   - `event_type`: `event.__struct__ |> Module.split() |> List.last()`
     - → `"ItemChecked"`
   - `data`: `Jason.encode!(Map.from_struct(event))`
2. `Repo.insert_all(Event, rows)`
3. Return `:ok` (rescue → `{:error, exception}`)

---

## Events Migration SQL

```sql
CREATE TABLE events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  stream_id   TEXT    NOT NULL,
  stream_type TEXT    NOT NULL,
  event_type  TEXT    NOT NULL,
  data        TEXT    NOT NULL,
  metadata    TEXT,
  inserted_at TEXT    NOT NULL
);

CREATE INDEX idx_events_stream ON events (stream_id, id);
```

Expressed as Ecto migration DSL:

```elixir
create table(:events) do
  add :stream_id,   :string, null: false
  add :stream_type, :string, null: false
  add :event_type,  :string, null: false
  add :data,        :text,   null: false
  add :metadata,    :text
  timestamps(updated_at: false)
end

create index(:events, [:stream_id, :id])
```

---

## mix.exs — Dependencies to Add

| Dep | Version | Reason |
|-----|---------|--------|
| `req` | `~> 0.5` | HTTP adapter (Phase 6 scraping; stub in Phase 1) |
| `mox` | `~> 1.2`, `only: :test` | Mock LLM + HTTP ports in handler tests |

No Quantum yet — scheduler.ex will be a placeholder module.

---

## config/config.exs — Additions

```elixir
config :scullion, :llm_client, Scullion.Adapters.OpenRouter
config :scullion, :http_client, Scullion.Adapters.ReqHTTP
```

These let handlers read the adapter via `Application.compile_env/2`. The adapters are stubs in Phase 1 — all callbacks return `{:error, :not_implemented}`.
