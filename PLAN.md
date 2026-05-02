# Phase 3 — Data Model & Recipe Persistence

## Overview

Implement the full Recipes context: migrations, Ecto schemas, CRUD context, HTML parser
(pure), RecipeHandler (scrape + LLM fallback + image generation), ImageGen port + stub
adapter, and the recipe CRUD LiveView with search, filtering, and sorting.

Phase 3 is self-contained. It touches Recipes, one new port (ImageGen), one new adapter
stub, RecipeHandler, and one new LiveView. It does not touch Planning, Groceries, or any
other context.

---

## New dependency

```elixir
{:floki, "~> 0.37"}
```

Floki is a pure-Elixir HTML parser used by `Recipes.Parser` to extract JSON-LD/microdata
from recipe pages. No other new deps.

---

## New migrations (4 files)

### priv/repo/migrations/20260502000004_create_recipes.exs

```sql
CREATE TABLE recipes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT,
  instructions TEXT,
  recipe_type TEXT NOT NULL DEFAULT 'meal',  -- meal / component / assembly
  base_servings INTEGER,
  prep_time_minutes INTEGER,
  cook_time_minutes INTEGER,
  source_url TEXT,
  video_url TEXT,
  image_path TEXT,
  last_used_at TEXT,
  created_by INTEGER,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### priv/repo/migrations/20260502000005_create_ingredients.exs

```sql
CREATE TABLE ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  category TEXT,
  default_unit TEXT,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_ingredients_name ON ingredients(name);
```

### priv/repo/migrations/20260502000006_create_recipe_ingredients.exs

```sql
CREATE TABLE recipe_ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
  quantity DECIMAL,
  unit TEXT,
  notes TEXT,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients(recipe_id);
```

### priv/repo/migrations/20260502000007_create_tags.exs

```sql
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_tags_name ON tags(name);

CREATE TABLE recipe_tags (
  recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (recipe_id, tag_id)
);
```

---

## Files to create (new)

### lib/scullion/image_gen.ex

New port behaviour. Kept separate from LLM since the provider may differ.

```elixir
defmodule Scullion.ImageGen do
  @callback generate_food_image(title :: String.t(), ingredients :: [String.t()])
            :: {:ok, binary()} | {:error, term()}
end
```

### lib/scullion/adapters/stub_image_gen.ex

Stub adapter for dev/test — returns a fixed placeholder PNG binary (1×1 transparent PNG).
Wired in dev and test config. The real OpenRouter/DALL-E adapter comes in Phase 5.

```elixir
config :scullion, :image_gen_client, Scullion.Adapters.StubImageGen
```

### lib/scullion/recipes/recipe_tag.ex (new join schema)

```elixir
schema "recipe_tags" do
  belongs_to :recipe, Recipe
  belongs_to :tag, Tag
end
```

No timestamps — pure join table.

---

## Files to modify

### lib/scullion/recipes/recipe.ex

Replace stub schema with full implementation.

```elixir
schema "recipes" do
  field :title, :string
  field :description, :string
  field :instructions, :string
  field :recipe_type, Ecto.Enum, values: [:meal, :component, :assembly], default: :meal
  field :base_servings, :integer
  field :prep_time_minutes, :integer
  field :cook_time_minutes, :integer
  field :source_url, :string
  field :video_url, :string
  field :image_path, :string
  field :last_used_at, :utc_datetime
  field :created_by, :integer

  has_many :recipe_ingredients, RecipeIngredient
  many_to_many :tags, Tag, join_through: RecipeTag, on_replace: :delete

  timestamps()
end

def changeset(recipe, attrs)          # create/update: title required, types validated
def tag_changeset(recipe, tags)       # replace associated tags
```

### lib/scullion/recipes/ingredient.ex

Replace stub with full implementation.

```elixir
schema "ingredients" do
  field :name, :string
  field :category, :string
  field :default_unit, :string

  has_many :recipe_ingredients, RecipeIngredient
  timestamps()
end

def changeset(ingredient, attrs)      # name required, unique_constraint on name
```

### lib/scullion/recipes/recipe_ingredient.ex

Replace stub with associations.

```elixir
schema "recipe_ingredients" do
  belongs_to :recipe, Recipe
  belongs_to :ingredient, Ingredient
  field :quantity, :decimal
  field :unit, :string
  field :notes, :string
  timestamps()
end

def changeset(ri, attrs)
```

### lib/scullion/recipes/tag.ex

Replace stub with full implementation.

```elixir
schema "tags" do
  field :name, :string
  many_to_many :recipes, Recipe, join_through: RecipeTag
  timestamps()
end

def changeset(tag, attrs)   # name required, unique_constraint on name
```

### lib/scullion/recipes/parser.ex

Replace stub with full JSON-LD + microdata extraction. Pure — no IO.

```elixir
def parse_html(html :: String.t()) :: {:ok, map()} | {:error, :not_found}
```

Strategy:
1. Use Floki to find `<script type="application/ld+json">` — try all, pick first with
   `@type` of `"Recipe"`. Decode JSON, map LD fields to recipe attrs.
2. If no JSON-LD: look for microdata (`itemtype="http://schema.org/Recipe"`). Extract
   `itemprop` values.
3. If neither: `{:error, :not_found}` → caller falls back to LLM.

Returned map keys (all optional except `:title`):
```elixir
%{
  title: String.t(),
  description: String.t(),
  instructions: String.t(),           # joined if list
  prep_time_minutes: integer(),       # parse ISO 8601 duration PT15M → 15
  cook_time_minutes: integer(),
  base_servings: integer(),
  ingredients: [%{name: String.t(), quantity: String.t(), unit: String.t()}],
  image_url: String.t()               # first image URL from the page, if any
}
```

### lib/scullion/recipes.ex

Replace stubs with full implementation.

```elixir
# Public API
def create(attrs)                     # insert recipe + upsert ingredients + tags, trigger image gen
def update(recipe, attrs)             # update recipe fields and tag associations
def get!(id)                          # Repo.get! with :tags, :recipe_ingredients preloaded
def list(opts \\ [])                  # see filtering/sorting below
def search(query)                     # full-text by title + ingredient names (SQL LIKE)
def record_used(recipe_id)            # set last_used_at = utc_now
def scrape_from_url(url)              # delegate to RecipeHandler.scrape_and_create/1
```

**`list/1` opts:**
- `tags: ["batch", "quick"]` — recipes that have ALL listed tags
- `type: :meal | :component | :assembly`
- `max_minutes: integer()` — filter by (prep_time_minutes + cook_time_minutes) ≤ N
- `weeknight_friendly: true` — equivalent to `tags: ["quick"], max_minutes: 45`
- `sort: :last_used | :alphabetical | :recently_added` — default `:recently_added`

**`create/1`** implementation notes:
- Upsert ingredients by name (`Repo.insert(..., on_conflict: :nothing, conflict_target: :name)`)
- Look up or create tag records by name
- After successful recipe insert, call image generation asynchronously via `Task.start/1`:
  - If `attrs[:image_url]` is present (from scraping): download and save it
  - Else: call `@image_gen.generate_food_image(title, ingredient_names)` → save binary
  - Store as `priv/static/uploads/recipes/#{recipe.id}.jpg`
  - Update recipe `image_path` field

### lib/scullion/handlers/recipe_handler.ex

Expand stub to full implementation.

```elixir
@http Application.compile_env(:scullion, :http_client)
@llm Application.compile_env(:scullion, :llm_client)
@image_gen Application.compile_env(:scullion, :image_gen_client)

def scrape_and_create(url)
# 1. @http.fetch(url) → html
# 2. Parser.parse_html(html) → {:ok, attrs} | {:error, :not_found}
# 3. on :not_found → @llm.extract_recipe_from_html(html)
# 4. Set source_url from url
# 5. Recipes.create(attrs)
# Returns {:ok, recipe} | {:error, reason}

def generate_image(recipe)
# Called from Recipes.create async task
# Determines: download source image OR call @image_gen
# Saves file, updates recipe.image_path
# Returns :ok | {:error, reason}
```

Image save path: `Path.join([:code.priv_dir(:scullion), "static", "uploads", "recipes",
"#{recipe.id}.jpg"])`. Directory created if absent.

### lib/scullion_web/live/recipe_live.ex

Replace stub with full CRUD + search LiveView.

**State:**
```elixir
%{
  recipes: [Recipe.t()],
  search: String.t(),
  filter_tags: [String.t()],
  filter_type: :all | :meal | :component | :assembly,
  filter_max_min: :any | 30 | 45 | 60,
  sort: :recently_added | :last_used | :alphabetical,
  scrape_url: String.t(),
  scrape_state: :idle | :loading | :reviewing,
  scrape_result: map() | nil,
  form: Phoenix.HTML.Form.t() | nil,
  selected: Recipe.t() | nil,
  error: String.t() | nil
}
```

**Events:**
- `"search"` — update search string, reload list
- `"filter_tag"` — toggle a tag in filter_tags, reload
- `"filter_type"` — set recipe type filter, reload
- `"filter_time"` — set max_minutes filter, reload
- `"sort"` — change sort order, reload
- `"new_recipe"` — show blank form
- `"save_recipe"` — call Recipes.create or Recipes.update
- `"select_recipe"` — show detail view
- `"edit_recipe"` — show edit form for selected
- `"delete_recipe"` — call Recipes.delete (soft: set deleted_at or hard delete)
- `"scrape_url_change"` — update scrape_url
- `"scrape_submit"` — call Recipes.scrape_from_url asynchronously
- `"confirm_scraped"` — user reviews parsed attrs, calls Recipes.create
- `"discard_scraped"` — reset scrape state

**List loading**: `Recipes.list(search: @search, tags: @filter_tags, type: @filter_type, max_minutes: @filter_max_min, sort: @sort)` — called on every filter/sort change.

The LiveView does not contain Ecto queries. All list/search calls go through `Recipes`.

---

## Test files to create

### test/scullion/recipes/parser_test.exs

Pure unit tests — no DB, no mocks.

```
describe "parse_html/1 (JSON-LD)"
  test "extracts title, ingredients, times from JSON-LD"
  test "joins instruction list into text"
  test "parses ISO 8601 duration PT1H30M → 90 minutes"
  test "returns :not_found when no Recipe type in ld+json"

describe "parse_html/1 (microdata)"
  test "extracts title from itemprop=name"
  test "extracts ingredient list"

describe "parse_html/1 (neither)"
  test "returns {:error, :not_found}"
```

Use inline HTML fixtures — no file IO needed.

### test/scullion/recipes_test.exs

```
describe "create/1"
  test "inserts recipe with tags and ingredients"
  test "upserts ingredients (no duplicate names)"
  test "returns error for missing title"

describe "list/1"
  test "filters by tag"
  test "filters by type"
  test "filters by max_minutes"
  test "sorts by alphabetical"
  test "weeknight_friendly filter"

describe "search/1"
  test "matches by title"
  test "matches by ingredient name"
  test "returns empty list for no match"

describe "update/2"
  test "updates fields and replaces tags"

describe "record_used/1"
  test "sets last_used_at"
```

Image generation calls must be mocked: configure `Scullion.Adapters.StubImageGen` in
test and verify `image_path` is set without actual file writes (or use a temp dir).

### test/scullion/handlers/recipe_handler_test.exs

Uses Mox for `Scullion.HTTP` and `Scullion.LLM`.

```
describe "scrape_and_create/1"
  test "uses Parser result when JSON-LD found" (stub HTTP → html with ld+json, Parser succeeds)
  test "falls back to LLM when Parser returns not_found" (stub HTTP + stub LLM)
  test "propagates HTTP error"
```

---

## Mox setup additions

Add to `test/support/mocks.ex` (or create if absent):

```elixir
Mox.defmock(Scullion.MockImageGen, for: Scullion.ImageGen)
```

Add to `test/support/fixtures.ex` (or inline):

```elixir
def stub_image_gen(_title, _ingredients), do: {:ok, <<137, 80, 78, 71, ...>>}  # 1x1 PNG
```

Wire in `test.exs`:
```elixir
config :scullion, :image_gen_client, Scullion.Adapters.StubImageGen
```

---

## Implementation order

1. `mix.exs` — add `{:floki, "~> 0.37"}`; `mix deps.get`
2. Migrations 004–007 — write, `mix ecto.migrate`
3. `image_gen.ex` — port behaviour
4. `adapters/stub_image_gen.ex` — stub adapter (returns 1×1 PNG binary)
5. `config/dev.exs` + `config/test.exs` — wire `image_gen_client` to stub
6. `recipes/recipe_tag.ex` — join schema
7. `recipes/tag.ex` — full schema + changeset
8. `recipes/ingredient.ex` — full schema + changeset
9. `recipes/recipe_ingredient.ex` — full schema + changeset
10. `recipes/recipe.ex` — full schema + changesets + associations
11. `recipes/parser.ex` — JSON-LD and microdata extraction with Floki
12. `recipes.ex` — full CRUD implementation
13. `handlers/recipe_handler.ex` — expand to full scrape + image gen flow
14. `recipe_live.ex` — CRUD + search + scrape LiveView
15. Tests: `parser_test.exs`, `recipes_test.exs`, `recipe_handler_test.exs`
16. `mix compile --warnings-as-errors && mix test`

---

## Unknowns / decisions deferred

- **Recipe deletion**: hard delete for now (no `deleted_at`). Easy to change later.
- **Image storage format**: save as JPEG regardless of source. Source URL images are
  fetched and stored as-is. Generated images assumed JPEG from the API.
- **Image uploads from UI**: not in Phase 3. Manual recipe creation via LiveView form
  only sets text fields — image generated from title+ingredients automatically.
- **`Recipes.delete/1`**: implement as `Repo.delete/1`. No soft-delete at this stage.
- **ImageGen adapter (real)**: deferred to Phase 5 alongside the OpenRouter LLM adapter.
  Both require OpenRouter config which is also Phase 5.
