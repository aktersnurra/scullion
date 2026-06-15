# Tore

![tore](priv/static/images/logo.svg)

An AI-assisted meal planner built with Phoenix LiveView — named as a homage to [Tore Wretman](https://sv.wikipedia.org/wiki/Tore_Wretman), the father of modern Swedish cuisine.

---

## What it does

- **Weekly meal planning** — AI generates a full week of dinners from your recipe catalog, respecting pantry stock, current supermarket deals, and dietary guidance you configure.
- **Recipe management** — scrape recipes from URLs, parse receipts from photos, store and browse your collection. Recipes are translated into your locale at import time.
- **Pantry tracking** — log what you have at home; the planner and grocery list use it automatically.
- **Grocery list** — auto-generated from the week's plan, aggregated by ingredient.
- **Deal scraping** — pulls current deals from ICA and Coop; the planner biases toward cheap ingredients.
- **Cost tracking** — log receipts and dining-out expenses; summarised on the cost view.
- **Per-slot suggestions** — open any meal slot to get ranked recipe suggestions (rule-based + one LLM pick).
- **Dietary guidance** — free-text field in settings, injected as a constraint into every LLM prompt.
- **Localisation** — full Swedish UI via Gettext; locale stored per user.

---

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Phoenix 1.8, LiveView |
| Database | SQLite via Ecto + Exqlite |
| LLM / vision | OpenRouter (configurable model per use-case) |
| Image generation | OpenRouter image model |
| Structured outputs | OpenRouter `json_schema` response format |
| Markdown rendering | MDEx (CommonMark, Rust NIF) |
| Scheduling | Quantum |
| Auth | Magic-link tokens + device tokens for kiosk mode |

---

## Architecture

```
lib/
├── tore/
│   ├── accounts/         # Users, login tokens, device tokens, rate limiter
│   ├── adapters/         # OpenRouter LLM/image adapter, Req HTTP adapter, stubs
│   ├── costs/            # Receipts, line items, dining-out, LLM usage tracking
│   ├── deals/            # Deal schema, store configs, ICA/Coop parsers
│   ├── groceries/        # Grocery list decider (event-sourced)
│   ├── handlers/         # Application layer: planning, recipe, costs, deals, prep, groceries
│   ├── llm/              # Prompt builders (plan_weekly, suggest_slot_recipe, extract_recipe, …)
│   ├── pantry/           # Pantry inventory
│   ├── planning/         # Weekly plan decider (event-sourced), commands, events, state
│   ├── prep/             # Prep guides
│   └── recipes/          # Recipe, Ingredient (with canonical keys), Tag, Parser
└── tore_web/
    ├── components/       # Core UI components, layouts
    ├── controllers/      # Page, session, error controllers
    ├── live/             # All LiveView modules (planner, recipe, pantry, grocery, cost, settings, …)
    └── plugs/            # Auth, device auth, locale
```

### Key patterns

**Event sourcing** — planning and grocery list state are derived from an append-only event log (`Tore.EventStore`). The `Decider` pattern: `decide(command, state) → events`, `evolve(state, event) → state`.

**Handler layer** — `Tore.Handlers.*` sit between LiveViews and domain logic. They orchestrate DB reads, LLM calls, SpendGuard checks, and PubSub broadcasts.

**SpendGuard** — rate-limits LLM operations so a runaway loop can't drain API credits.

**Canonical ingredient keys** — ingredients store a `key` column (e.g. `gul_lok`) derived from the display name. Used for deduplication, pantry matching, and grocery aggregation across locales.

**Cheap pre-flight** — before calling the expensive extraction model on a scraped URL, a cheap free-tier model checks whether the HTML actually contains a recipe.

---

## Getting started

```sh
mix setup          # install deps, create and migrate DB, seed
mix phx.server     # http://localhost:4000
```

Set `OPENROUTER_API_KEY` in your environment (or `.env`). Optional overrides:

```sh
OPENROUTER_MODEL=openai/gpt-4o-mini
OPENROUTER_VISION_MODEL=google/gemini-2.5-flash-lite
OPENROUTER_IMAGE_MODEL=google/gemini-3.1-flash-image-preview
OPENROUTER_CHECK_MODEL=openai/gpt-oss-120b:free
```

### Local development with image storage (Garage)

Recipe images are stored in a local [Garage](https://garagehq.deuxfleurs.fr/)
(S3-compatible) instance, matching production. Requires Docker with the Compose
plugin.

```sh
bin/dev        # first run seeds .env and stops — fill it in, then re-run
```

`bin/dev` brings up Garage (`docker compose up -d --wait`), provisions the
`tore-recipes` bucket on first run, and starts Phoenix. Fill `.env` with:

- `OPENROUTER_API_KEY` — your OpenRouter key.
- `GARAGE_ACCESS_KEY_ID` / `GARAGE_SECRET_ACCESS_KEY` — credentials you choose
  (`GK`-prefixed id + 64-char hex secret; see the comments in `.env.example`).
  `bin/garage-bootstrap.sh` imports them into Garage.

Garage state persists in Docker named volumes, so restarts reuse it. To wipe and
re-provision from scratch: `docker compose down -v`, then `bin/dev` again.

Tests use an in-memory storage mock, so `mix test` needs nothing running.

---

## Running tests

```sh
mix test
```

232 tests, no external dependencies required (LLM and HTTP are mocked in test).
