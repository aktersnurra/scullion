# Scullion — Meal Planner & Kitchen Kiosk

> A scullion is the lowest-ranking kitchen servant — the one who peels, chops, scrubs pots,
> and does all the unglamorous prep work so the cook doesn't have to.

## Project Overview

A self-hosted meal planning system with two interfaces: a Raspberry Pi touchscreen kiosk
mounted in the kitchen, and a mobile-friendly web UI accessible from anywhere. It plans
weekly dinners, generates grocery lists, scrapes store deals, tracks food costs (groceries
and dining out), and uses an LLM to generate meal plans that account for deals, pantry
inventory, user preferences, and batch cooking (matlådor).

---

## Architecture

```
┌──────────────────────┐         ┌──────────────────────────────────┐
│  Raspberry Pi 5      │         │  VPS (gustafrydholm.xyz)         │
│  Nerves + kiosk      │         │                                  │
│  Chromium ──────────────HTTPS──▶  Phoenix + LiveView              │
│  (thin client)       │         │  Ecto + SQLite3                  │
│  Device token auth   │         │  OpenRouter LLM client           │
└──────────────────────┘         │  Quantum scheduler               │
                                 │  Deals + recipe scraping         │
┌──────────────────────┐         │  Let's Encrypt TLS               │
│  Phone / laptop      │         │                                  │
│  Browser ──────────────HTTPS──▶                                   │
│  16-digit code auth  │         └──────────────────────────────────┘
└──────────────────────┘
```

The **Pi is a thin client**. It runs Nerves with `kiosk_system_rpi5`, boots Chromium in
fullscreen pointing at `https://scullion.gustafrydholm.xyz`, and authenticates with a
long-lived device token. No Phoenix, no database, no business logic on the Pi.

The **server runs on the VPS**. All business logic, data, LLM calls, scraping, and image
parsing happen here. Both the kiosk and phone/laptop browsers connect to the same Phoenix app.

---

## Pattern Strategy: Deciders Where They Earn It, CRUD Everywhere Else

Two aggregates are event-sourced via the Decider pattern. Everything else is clean
Ecto CRUD with proper context boundaries.

### Event-sourced (Decider pattern)

| Aggregate     | Why                                                                        |
|---------------|----------------------------------------------------------------------------|
| **Groceries** | Multi-user real-time checklist. Granular events enable PubSub sync,        |
|               | conflict resolution, and natural undo. The poster child for this pattern.  |
| **Planning**  | LLM-orchestrated workflow with user tweaks. Enough commands (assign,       |
|               | remove, swap, set servings, mark leftover) to make the decider non-trivial.|

### CRUD (Ecto + context boundary)

| Context       | Why                                                                        |
|---------------|----------------------------------------------------------------------------|
| **Accounts**  | Create user, update preferences. Simple CRUD.                              |
| **Recipes**   | Reference data catalog. No decisions — just create, update, list, search.  |
| **Deals**     | Ephemeral. Scraped weekly, expire automatically. Upsert and query.         |
| **Pantry**    | Add/remove items. A simple inventory list.                                 |
| **Costs**     | Log receipts, log dining out. SQL queries for analytics — no event replay. |
| **Prep**      | LLM-generated text. Store and display.                                     |

All contexts — event-sourced or not — expose a clean public API module. LiveViews
only call these public APIs. No Ecto queries in LiveViews. Handlers orchestrate IO.

---

## Decider Flows

### Groceries: user checks off an item

```
1. grocery_live.ex: user taps checkbox
2. → handle_event("check_item", %{"id" => id}, socket)
3. → GroceriesHandler.check_item(list_id, item_id, user_id)
4.   → EventStore.load(list_id, Decider) → fold events → current state
5.   → Decider.decide(%CheckItem{...}, state) → {:ok, [%ItemChecked{...}]}
6.   → EventStore.append(list_id, events)
7.   → PubSub.broadcast("grocery_list:#{list_id}", {:events, events})
8. ← grocery_live receives broadcast → re-renders
```

### Planning: generate weekly plan (involves LLM IO)

```
1. planner_live.ex: user taps "Generate Plan"
2. → PlanningHandler.generate_plan(week, constraints)
3.   → load context: pantry, deals, preferences, recipe history
4.   → LLM.generate_plan(constraints_with_context)        ← IO (adapter call)
5.   → Decider.decide(%GeneratePlan{recipes: llm_result}, state) → {:ok, events}
6.   → EventStore.append(plan_id, events)
7.   → PubSub.broadcast(...)
8. ← planner_live re-renders
```

---

## Hardware (Pi Kiosk)

- **Board**: Raspberry Pi 5 (8GB)
- **Display**: 10.1" Waveshare DSI capacitive touchscreen (1280×800)
  - Fallback: official Pi Touch Display 2 (7")
- **Storage**: MicroSD (thin client, minimal writes — NVMe not needed)
- **Accessories**: Pi 5 active cooler, official 27W USB-C PSU

## Stack (VPS Server)

- **Language**: Elixir
- **Web framework**: Phoenix + LiveView
- **Database**: Ecto + SQLite3 (via `ecto_sqlite3`) — two users, no bloat
- **Scheduler**: Quantum (OTP-native cron)
- **LLM provider**: OpenRouter via `Req`
- **HTTP client**: `Req` (for OpenRouter API, web scraping, recipe fetching)
- **TLS**: Let's Encrypt (via Certbot or Caddy reverse proxy)

## Stack (Pi Firmware)

- **OS/Firmware**: Nerves using `kiosk_system_rpi5`
- **Browser**: Chromium fullscreen kiosk mode
- **Networking**: VintageNet for WiFi
- **Config**: device token + server URL stored on writable data partition

---

## Authentication

### Mullvad-style Account Codes (humans)

No usernames, no emails, no passwords. Each user gets a single **16-digit numeric code**
that serves as both identity and credential. Displayed grouped: `XXXX XXXX XXXX XXXX`.

- **Generation**: cryptographically random, unique
- **Storage**: Argon2-hashed in the DB
- **Login UI**: numpad with large touch targets — works with wet/floury hands on kiosk,
  works on phone
- **Rate limiting**: exponential backoff + IP lockout after 5 failed attempts
- **Sessions**: long-lived session token in a cookie

### Device Token (kiosk)

The Pi authenticates with a **long random token** (e.g. 64-char hex string), provisioned once:
1. Admin generates a device token from the settings UI
2. Token is entered/configured on the Pi (stored in Nerves data partition)
3. Pi sends token in a header or query param on every request
4. Server validates and assigns the `kiosk` role — no login screen shown

If the Pi is compromised, revoke the device token from the admin UI without affecting user accounts.

### Three Roles

| Role       | Auth method        | Capabilities                                                                                      |
|------------|--------------------|---------------------------------------------------------------------------------------------------|
| **kiosk**  | Device token       | View calendar, recipes, grocery list, prep guide. Check off grocery items. No settings, no uploads, no user management. |
| **member** | 16-digit code      | Everything kiosk can do, plus: upload receipt photos, log dining out, add manual grocery items, request recipe suggestions, manage own preferences. |
| **admin**  | 16-digit code      | Everything member can do, plus: manage users (generate/revoke codes), configure stores, configure OpenRouter, trigger scheduled jobs, manage device tokens. |

### First Boot

1. Server starts with no users
2. First visitor hits the setup page → enters a display name → system generates a 16-digit admin code
3. Code is shown once — user saves it
4. Setup page is disabled after first account creation

---

## Project Structure

```
scullion/
├── lib/
│   ├── scullion/
│   │   │
│   │   │── ─── EVENT-SOURCED AGGREGATES (Decider pattern) ───
│   │   │
│   │   ├── planning/
│   │   │   ├── decider.ex              # decide/2, evolve/2, initial/0 — pure, zero IO
│   │   │   │                            #   Commands: GeneratePlan, AssignRecipe, RemoveRecipe,
│   │   │   │                            #             SetServings, MarkLeftover
│   │   │   │                            #   Events:   PlanGenerated, RecipeAssigned, RecipeRemoved,
│   │   │   │                            #             ServingsChanged, LeftoverMarked
│   │   │   │                            #   State:    %PlanState{week_start, slots: %{day => slot}}
│   │   │   ├── commands.ex
│   │   │   ├── events.ex
│   │   │   └── state.ex
│   │   │
│   │   ├── groceries/
│   │   │   ├── decider.ex              # decide/2, evolve/2, initial/0 — pure, zero IO
│   │   │   │                            #   Commands: BuildList, AddItem, RemoveItem,
│   │   │   │                            #             CheckItem, UncheckItem
│   │   │   │                            #   Events:   ListBuilt, ItemAdded, ItemRemoved,
│   │   │   │                            #             ItemChecked, ItemUnchecked
│   │   │   ├── commands.ex
│   │   │   ├── events.ex
│   │   │   ├── state.ex
│   │   │   └── aggregator.ex           # Pure: [Recipe] → merged [GroceryItem]
│   │   │                                # Unit conversion, deduplication
│   │   │
│   │   │── ─── CRUD CONTEXTS (Ecto, clean public API) ───
│   │   │
│   │   ├── accounts.ex                  # Public API: create_user, authenticate,
│   │   │                                #   update_preferences, generate_device_token, revoke, etc.
│   │   ├── accounts/
│   │   │   ├── user.ex                 # Ecto schema
│   │   │   └── device_token.ex         # Ecto schema
│   │   │
│   │   ├── recipes.ex                   # Public API: create, update, list, search, get,
│   │   │                                #   scrape_from_url
│   │   ├── recipes/
│   │   │   ├── recipe.ex               # Ecto schema
│   │   │   ├── ingredient.ex           # Ecto schema
│   │   │   ├── recipe_ingredient.ex    # Ecto join schema
│   │   │   ├── tag.ex                  # Ecto schema
│   │   │   └── parser.ex              # Pure: HTML → structured recipe data
│   │   │                                # JSON-LD, microdata, common patterns
│   │   │
│   │   ├── deals.ex                     # Public API: upsert_deals, list_current, clear_expired
│   │   ├── deals/
│   │   │   ├── deal.ex                 # Ecto schema
│   │   │   ├── store_config.ex         # Ecto schema
│   │   │   └── parsers/
│   │   │       ├── parser.ex           # Behaviour: parse(html) :: {:ok, [deal_attrs]}
│   │   │       ├── ica.ex
│   │   │       └── coop.ex
│   │   │
│   │   ├── pantry.ex                    # Public API: add_item, remove_item, list_inventory
│   │   ├── pantry/
│   │   │   └── pantry_item.ex          # Ecto schema
│   │   │
│   │   ├── costs.ex                     # Public API: log_receipt, log_dining_out,
│   │   │                                #   weekly_summary, monthly_summary, cost_per_meal
│   │   ├── costs/
│   │   │   ├── receipt.ex              # Ecto schema
│   │   │   ├── line_item.ex            # Ecto schema (product, quantity, unit_price, total_price)
│   │   │   └── dining_out.ex           # Ecto schema
│   │   │
│   │   ├── prep.ex                      # Public API: save_guide, get_guide_for_week
│   │   ├── prep/
│   │   │   └── prep_guide.ex           # Ecto schema
│   │   │
│   │   │── ─── INFRASTRUCTURE ───
│   │   │
│   │   ├── event_store.ex              # Append events, load stream, fold to state
│   │   │                                # SQLite-backed append-only events table
│   │   │                                # Used only by groceries + planning deciders
│   │   │                                # TODO: snapshots when streams get long
│   │   │
│   │   │── ─── HANDLERS (imperative shell, orchestrates IO) ───
│   │   │
│   │   ├── handlers/
│   │   │   ├── planning_handler.ex     # Load state → call LLM → decide → persist → broadcast
│   │   │   ├── groceries_handler.ex    # Load state → decide → persist → broadcast
│   │   │   ├── recipe_handler.ex       # Call HTTP + LLM (scrape) → Recipes CRUD
│   │   │   ├── deals_handler.ex        # Call HTTP → parse → Deals CRUD
│   │   │   ├── costs_handler.ex        # Call LLM (receipt OCR) → Costs CRUD
│   │   │   └── prep_handler.ex         # Call LLM (prep guide) → Prep CRUD
│   │   │
│   │   │── ─── PORTS (behaviours) ───
│   │   │
│   │   ├── llm.ex                      # @callback generate_plan/1, suggest_recipes/1,
│   │   │                                #   extract_recipe_from_html/1, parse_receipt_image/1,
│   │   │                                #   parse_deals_image/1, generate_prep_guide/1
│   │   │
│   │   └── http.ex                     # @callback fetch(url) :: {:ok, body} | {:error, reason}
│   │
│   │── ─── ADAPTERS ───
│   │
│   ├── scullion/adapters/
│   │   ├── open_router.ex              # Implements Scullion.LLM
│   │   └── req_http.ex                 # Implements Scullion.HTTP
│   │
│   │── ─── WEB LAYER ───
│   │
│   ├── scullion_web/
│   │   ├── live/
│   │   │   ├── setup_live.ex            # First-boot admin creation
│   │   │   ├── login_live.ex            # Numpad → Accounts.authenticate
│   │   │   ├── planner_live.ex          # → PlanningHandler + PubSub subscribe
│   │   │   ├── recipe_live.ex           # → RecipeHandler / Recipes context
│   │   │   ├── grocery_live.ex          # → GroceriesHandler + PubSub subscribe
│   │   │   ├── prep_live.ex             # → PrepHandler / Prep context
│   │   │   ├── deals_live.ex            # → DealsHandler / Deals context
│   │   │   ├── pantry_live.ex           # → Pantry context
│   │   │   ├── cost_live.ex             # → CostsHandler / Costs context
│   │   │   └── settings_live.ex         # → Accounts context (admin only)
│   │   ├── plugs/
│   │   │   ├── auth.ex                  # Session-based (16-digit code)
│   │   │   └── device_auth.ex           # Device token (kiosk)
│   │   ├── components/                  # Reusable LiveView function components
│   │   └── router.ex
│   │
│   ├── scullion/scheduler.ex           # Quantum jobs:
│   │                                    #   Sat 08:00 → DealsHandler.scrape_all
│   │                                    #   Sat 18:00 → PlanningHandler.generate_plan
│   │                                    #   Sat 18:30 → PrepHandler.generate_guide
│   │
│   └── scullion.ex                     # Application supervision tree
│
├── test/
│   ├── scullion/
│   │   ├── planning/decider_test.exs   # Pure: no mocks, no IO
│   │   ├── groceries/decider_test.exs  # Pure: no mocks, no IO
│   │   ├── groceries/aggregator_test.exs
│   │   ├── recipes/parser_test.exs     # Pure: HTML → recipe attrs
│   │   ├── deals/parsers/ica_test.exs  # Pure: HTML → deal attrs
│   │   ├── handlers/                   # Mock ports via Mox
│   │   ├── accounts_test.exs           # Ecto sandbox
│   │   ├── costs_test.exs
│   │   └── pantry_test.exs
│   ├── scullion/adapters/              # Integration tests
│   └── scullion_web/                   # LiveView tests
│
├── priv/repo/migrations/
│   ├── 001_create_events.exs           # Append-only event log (groceries + planning)
│   ├── 002_create_users.exs
│   ├── 003_create_device_tokens.exs
│   ├── 004_create_recipes.exs
│   ├── 005_create_ingredients.exs
│   ├── 006_create_recipe_ingredients.exs
│   ├── 007_create_tags.exs
│   ├── 008_create_deals.exs
│   ├── 009_create_store_configs.exs
│   ├── 010_create_pantry_items.exs
│   ├── 011_create_receipts.exs
│   ├── 012_create_line_items.exs
│   ├── 013_create_dining_out.exs
│   └── 014_create_prep_guides.exs
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── test.exs                        # Wire ports to Mox mocks
│   └── runtime.exs                     # OpenRouter API key, etc.
└── mix.exs
```

Separate repo for the Pi firmware:

```
scullion_kiosk/
├── lib/
│   └── scullion_kiosk/
│       ├── application.ex
│       └── kiosk.ex
├── config/
│   ├── config.exs
│   ├── host.exs
│   └── target.exs
├── rootfs_overlay/
└── mix.exs
```

---

## Key Module Signatures

### Decider (pure, zero IO)

```elixir
defmodule Scullion.Groceries.Decider do
  alias Scullion.Groceries.{State, Commands, Events}

  @spec initial() :: State.t()
  def initial, do: %State{}

  @spec decide(Commands.t(), State.t()) :: {:ok, [Events.t()]} | {:error, term()}
  def decide(%Commands.CheckItem{} = cmd, state), do: ...

  @spec evolve(State.t(), Events.t()) :: State.t()
  def evolve(state, %Events.ItemChecked{} = e), do: ...
end
```

### Handler (imperative shell — decider aggregate)

```elixir
defmodule Scullion.Handlers.GroceriesHandler do
  alias Scullion.{EventStore, Groceries.Decider, Groceries.Commands}

  def check_item(list_id, item_id, user_id) do
    command = %Commands.CheckItem{item_id: item_id, checked_by: user_id}

    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(list_id, events) do
      PubSub.broadcast("grocery_list:#{list_id}", {:events, events})
      {:ok, events}
    end
  end
end
```

### Handler (imperative shell — CRUD context with IO)

```elixir
defmodule Scullion.Handlers.CostsHandler do
  @llm Application.compile_env(:scullion, :llm_client)

  def parse_and_log_receipt(image_binary, user_id) do
    with {:ok, line_items} <- @llm.parse_receipt_image(image_binary) do
      Scullion.Costs.log_receipt(%{
        line_items: line_items,
        user_id: user_id,
        image_path: store_image(image_binary)
      })
    end
  end
end
```

### CRUD Context (clean public API)

```elixir
defmodule Scullion.Costs do
  alias Scullion.Costs.{Receipt, LineItem, DiningOut}
  alias Scullion.Repo

  def log_receipt(attrs), do: ...
  def log_dining_out(attrs), do: ...
  def weekly_summary(week_start), do: ...
  def monthly_summary(year, month), do: ...
  def cost_per_meal(period), do: ...
end
```

### Event Store

```elixir
defmodule Scullion.EventStore do
  @spec load(stream_id :: String.t(), decider :: module()) :: {:ok, state}
  @spec append(stream_id :: String.t(), events :: [struct()]) :: :ok | {:error, term()}
end
```

### Port (behaviour)

```elixir
defmodule Scullion.LLM do
  @callback generate_plan(constraints :: map()) :: {:ok, map()} | {:error, term()}
  @callback suggest_recipes(context :: map()) :: {:ok, [map()]} | {:error, term()}
  @callback extract_recipe_from_html(html :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback parse_receipt_image(image :: binary()) :: {:ok, [map()]} | {:error, term()}
  @callback parse_deals_image(image :: binary()) :: {:ok, [map()]} | {:error, term()}
  @callback generate_prep_guide(plan :: map()) :: {:ok, map()} | {:error, term()}
end
```

---

## Event Store Schema

```sql
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  stream_id TEXT NOT NULL,          -- e.g. "grocery_list:2026-w18", "plan:2026-w18"
  stream_type TEXT NOT NULL,        -- "groceries" or "planning"
  event_type TEXT NOT NULL,         -- e.g. "ItemChecked", "RecipeAssigned"
  data TEXT NOT NULL,               -- JSON-encoded event payload
  metadata TEXT,                    -- JSON: user_id, timestamp, correlation_id
  inserted_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_events_stream ON events(stream_id, id);
```

---

## Data Model (CRUD tables)

```
User
  - name, account_code_hash, role (admin / member)
  - preferences: map (allergies, dislikes, dietary constraints)

DeviceToken
  - token_hash, name ("kitchen kiosk")
  - revoked_at (nullable — soft revoke)

Recipe
  - title, description, instructions (text/markdown)
  - base_servings, prep_time_minutes, cook_time_minutes
  - source_url (original website), video_url (YouTube etc.)
  - last_used_at (for rotation tracking)
  - created_by: user_id (nullable — null if LLM-generated)
  - has_many: recipe_ingredients, tags (through recipe_tags)

Ingredient
  - name, category (produce / dairy / meat / pantry / spice / etc.)
  - default_unit

RecipeIngredient (join table)
  - recipe_id, ingredient_id
  - quantity, unit, notes ("finely diced", "optional")

Tag
  - name ("quick", "vegetarian", "batch-friendly", "swedish", "asian", etc.)

Deal
  - store (ica / coop / other), store_location
  - product_name, brand, size, price, price_unit, offer_condition
  - valid_from, valid_until
  - source (scraped / vision / manual)

StoreConfig
  - name, chain (ica / coop), store_id, url
  - scrape_enabled (boolean)

PantryItem
  - name, quantity, unit, category
  - ingredient_id (nullable)
  - added_at, expires_at (optional)

Receipt
  - date, store_name, total_amount
  - image_path (original photo)
  - user_id (who uploaded)
  - has_many: line_items

LineItem
  - receipt_id
  - product_name, quantity, unit_price, total_price

DiningOut
  - date, description (restaurant name, occasion, etc.)
  - total_amount, num_people
  - user_id (who logged it)

PrepGuide
  - week_start (date)
  - instructions (markdown from LLM)
  - timeline (list of maps, stored as JSON)
```

Note: MealPlan and GroceryList state live in the event store, not in CRUD tables.
Their current state is reconstructed by folding events through the decider's `evolve/2`.

---

## Design Principles

- **Deciders where they earn it, CRUD everywhere else.** Two event-sourced aggregates
  (groceries + planning) where the pattern provides real value. Everything else is
  Ecto CRUD with clean context boundaries. Pragmatic, not purist.
- **Functional core / imperative shell.** Deciders are pure functions with zero IO.
  Handlers orchestrate IO (LLM calls, HTTP fetches) before/after the pure decision.
  CRUD handlers orchestrate IO then delegate to context modules.
- **Clean context boundaries everywhere.** Every context — event-sourced or CRUD —
  exposes a public API module. LiveViews only call public APIs. No Ecto queries in LiveViews.
- **Behaviours for external deps.** LLM and HTTP behind behaviours. Adapters injected
  via config. Tests mock with Mox.
- **Port injection via config:**
  ```elixir
  # config/config.exs
  config :scullion, :llm_client, Scullion.Adapters.OpenRouter
  config :scullion, :http_client, Scullion.Adapters.ReqHTTP

  # config/test.exs
  config :scullion, :llm_client, Scullion.Mocks.LLMMock
  config :scullion, :http_client, Scullion.Mocks.HTTPMock
  ```

---

## Features (Sequential Build Order)

### Phase 1 — Skeleton & Deployment
- Phoenix project with LiveView + Ecto + SQLite3
- Project structure: domain contexts, handlers, ports, adapters
- EventStore module + events migration
- Deploy to VPS (systemd)
- Let's Encrypt TLS
- Basic page accessible via HTTPS

### Phase 2 — Auth & First Boot
- Accounts context: User + DeviceToken schemas, CRUD, Argon2 hashing
- First-boot setup flow (admin account creation)
- 16-digit account code generation
- Numpad login LiveView
- Rate limiting (exponential backoff + IP lockout)
- Session management (long-lived cookies)
- Role system (admin, member, kiosk)
- Device token generation + auth plug for kiosk

### Phase 3 — Data Model & Recipe Persistence
- Recipes context: Recipe, Ingredient, Tag, RecipeIngredient schemas
- Recipe CRUD via LiveView
- Tags/categories
- External links: source_url, video_url
- Recipe rotation tracking (last_used_at)
- Serving size field
- Recipe scraping from URLs:
  - Fetch HTML via HTTP port
  - Parse JSON-LD / microdata via Recipes.Parser (pure functions)
  - Fallback: LLM port extract_recipe_from_html
  - User provides URL → "scrape this" → review → persist

### Phase 4 — Weekly Planner & Grocery List
- Planning decider: GeneratePlan, AssignRecipe, RemoveRecipe, SetServings, MarkLeftover
- Groceries decider: BuildList, AddItem, RemoveItem, CheckItem, UncheckItem
- Groceries.Aggregator: pure function merging recipe ingredients into grocery items
- Calendar LiveView: week grid, tap day → recipe
- Grocery list LiveView: real-time sync via PubSub
- Category-grouped display

### Phase 5 — LLM Integration
- Scullion.LLM behaviour + Scullion.Adapters.OpenRouter
- Generate weekly plan: constraints → LLM → PlanningHandler → Decider
- Suggest new recipe: pantry/groceries context → LLM → alternatives
- Meal prep guide: PrepHandler → LLM → Prep context (CRUD save)
  - Consolidated Sunday prep instructions for Mon–Fri
  - Prep timeline, ingredient overlap optimisation
- Matlådor: servings multiplier on plan, LLM adjusts grocery quantities
- Structured output parsing (JSON mode)

### Phase 6 — Deals Scraping
- Deals context: Deal, StoreConfig schemas, CRUD
- Parser behaviour with ICA + Coop implementations (pure HTML parsing)
- Scheduled scrape (Quantum, Saturday morning): HTTP port → parser → Deals.upsert
- Ad-hoc URL scrape: paste URL → fetch → parse, LLM fallback
- Image/PDF upload: LLM port parse_deals_image → review UI → Deals.upsert
- Deals fed as context to LLM planner

#### ICA.se Scraping Notes
- Public offers: `https://www.ica.se/erbjudanden/{store-slug}-{store-id}/`
- Well-structured HTML: product names, brands, sizes, prices, offer conditions
- Store-specific — configure store ID in settings
- Personalised offers: screenshot/vision approach (ICA app login required)
- Weekly reklamblad: PDF via e-magin.se → vision/PDF extraction
- Old unofficial API (handla.api.ica.se) broke April 2024 — do not use

### Phase 7 — Cost Tracking
- Costs context: Receipt, LineItem, DiningOut schemas, CRUD + analytics queries
- Receipt parsing: photo upload → LLM port parse_receipt_image
  → line items (product, quantity, unit_price, total_price)
- Manual receipt entry fallback
- Manual correction UI for LLM-parsed results
- Dining out logging: date, restaurant, amount, num_people
- Cost analytics: weekly/monthly summaries, grocery vs dining out, cost-per-meal, trends

### Phase 8 — Pantry & Polish
- Pantry context: PantryItem schema, CRUD
- Checked-off grocery item → Pantry.add_item
- LLM uses pantry state to avoid re-buying
- Leftover awareness: MarkLeftover command on planning decider
- Nutritional estimates (LLM, rough macros)
- Grocery list export (plain text for SMS)

### Phase 9 — Kiosk Firmware
- Nerves project (scullion_kiosk) with kiosk_system_rpi5
- Chromium fullscreen → server URL
- Device token provisioned via config
- VintageNet WiFi
- OTA firmware updates via SSH

---

## Scheduling (Quantum)

| Job                      | Default Schedule        | Description                                              |
|--------------------------|------------------------|----------------------------------------------------------|
| Scrape ICA/Coop deals    | Saturday 08:00         | DealsHandler.scrape_all → HTTP → parse → Deals.upsert    |
| Generate weekly plan     | Saturday 18:00         | PlanningHandler → LLM → Decider → events                 |
| Generate prep guide      | Saturday 18:30         | PrepHandler → LLM → Prep.save_guide                      |

Triggerable manually from admin settings UI.

---

## Key Technical Decisions

1. **Server on VPS, Pi is thin client** — two separate repos.
2. **SQLite** — two users, single server, no bloat.
3. **Two event-sourced aggregates** — groceries + planning via Decider pattern.
   Everything else is CRUD. Pragmatic trade-off.
4. **LiveView for everything** — real-time sync via PubSub. No REST/GraphQL.
5. **OpenRouter only** — single LLM provider behind behaviour.
6. **Handlers as imperative shell** — orchestrate IO, delegate to deciders or CRUD contexts.
7. **Mullvad-style auth** — 16-digit codes, device tokens, Argon2 + rate limiting.
8. **Behaviours for deal parsers** — new store = implement one module.

---

## Macros

Do not introduce any macros until Phase 4 is complete. Write all 
handler and event boilerplate by hand first. After Phase 4, propose 
macro extractions based on observed repetition — do not design macros 
upfront. Any macro must be extracted from at least 3 existing instances 
of the same pattern.

---

## UI Considerations

- **Login**: numpad with large buttons, grouped digits (XXXX XXXX XXXX XXXX)
- **Kiosk (10.1", 1280×800)**: weekly calendar home, large tap targets, kitchen-safe
- **Mobile**: responsive LiveView, grocery list + receipt upload primary use cases
- **No native app** — browser only, add to homescreen

---

## Reference Material

- **Meal prep**: Andy's "What a Chef Eats in a Week" https://youtu.be/visxjkAQpTU
- **Auth**: Mullvad VPN account system https://mullvad.net
- **Nerves kiosk**: https://github.com/nerves-web-kiosk/kiosk_system_rpi5
- **ICA offers**: https://www.ica.se/erbjudanden/{store-slug}-{store-id}/
- **Decider pattern**: https://thinkbeforecoding.com/post/2021/12/17/functional-event-sourcing-decider
