# Phase 5 — LLM Integration

## Overview

Wire up the OpenRouter adapter and implement two LLM-powered flows:

1. **Weekly plan generation** — `PlanningHandler.generate_plan/3` calls OpenRouter,
   parses structured JSON output, fires the existing `GeneratePlan` command.
2. **Prep guide generation** — `PrepHandler.generate_guide/2` calls OpenRouter,
   persists structured guide via the `Prep` context.

Also in Phase 5: **SpendGuard** — gate + log every LLM call using OpenRouter's real
`cost` field. No guessing, no token math. Every LLM call is logged.

Everything else from the SPEC (suggest_recipe, lunchbox batch servings, receipt/deals
parsing) is later phases.

The Mox mocks (`Scullion.MockLLM`) and port injection config are already in place.
The `Scullion.Adapters.OpenRouter` stub exists. `PrepGuide` schema and `prep_guides`
migration exist.

---

## What already exists

**Stubs (need implementation):**
- `lib/scullion/adapters/open_router.ex` — all callbacks return `{:error, :not_implemented}`
- `lib/scullion/adapters/req_http.ex` — returns `{:error, :not_implemented}`
- `lib/scullion_web/live/planner_live.ex` — "Generate Plan" button is disabled

**Missing (need creation):**
- `lib/scullion/llm.ex` — behaviour module (referenced by adapter but doesn't exist yet)
- `lib/scullion/http.ex` — behaviour module (same)
- `lib/scullion/llm/prompts.ex` — rendering module
- `priv/llm/prompts/plan_weekly.eex` — prompt template
- `priv/llm/prompts/prep_guide.eex` — prompt template
- `lib/scullion/handlers/planning_handler.ex` — `generate_plan/3` (currently only manual commands)
- `lib/scullion/handlers/prep_handler.ex` — new handler
- `lib/scullion/prep.ex` — public API (only schema exists)
- `lib/scullion/spend_guard.ex` — budget gate
- `lib/scullion/llm/cost.ex` — cost extraction from OpenRouter response

**Config already wired:**
- `config :scullion, :llm_client, Scullion.Adapters.OpenRouter` (dev/prod)
- `config :scullion, :llm_client, Scullion.MockLLM` (test)
- `config :scullion, :http_client, Scullion.MockHTTP` (test)

---

## Port behaviours

### `lib/scullion/llm.ex` (new)

```elixir
defmodule Scullion.LLM do
  @callback generate_plan(constraints :: map()) :: {:ok, map(), usage :: map()} | {:error, term()}
  @callback suggest_recipes(context :: map()) :: {:ok, [map()], usage :: map()} | {:error, term()}
  @callback extract_recipe_from_html(html :: String.t()) :: {:ok, map(), usage :: map()} | {:error, term()}
  @callback parse_receipt_image(image :: binary()) :: {:ok, [map()], usage :: map()} | {:error, term()}
  @callback parse_deals_image(image :: binary()) :: {:ok, [map()], usage :: map()} | {:error, term()}
  @callback generate_prep_guide(plan :: map()) :: {:ok, map(), usage :: map()} | {:error, term()}
end
```

All callbacks return `{:ok, result, usage}` — usage is a map with at minimum `%{cost_usd: float}`.
This shape is uniform across all adapters including the mock.

### `lib/scullion/http.ex` (new)

```elixir
defmodule Scullion.HTTP do
  @callback fetch(url :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
```

---

## OpenRouter adapter

### `lib/scullion/adapters/open_router.ex` (replace stub)

Two callbacks implemented in Phase 5: `generate_plan/1` and `generate_prep_guide/1`.
The other four remain `{:error, :not_implemented}`.

OpenRouter returns `usage.cost` directly in every response — no token math needed.

**Shared internals:**
```elixir
@api_url "https://openrouter.ai/api/v1/chat/completions"

defp api_key, do: Application.fetch_env!(:scullion, :openrouter_api_key)
defp model, do: Application.get_env(:scullion, :openrouter_model, "anthropic/claude-3-5-haiku")

defp chat(system_prompt, user_prompt) do
  body = %{
    model: model(),
    response_format: %{type: "json_object"},
    messages: [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]
  }

  case Req.post(@api_url,
         json: body,
         headers: [
           {"Authorization", "Bearer #{api_key()}"},
           {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
           {"X-Title", "Scullion"}
         ]
       ) do
    {:ok, %{status: 200, body: body}} ->
      content = get_in(body, ["choices", Access.at(0), "message", "content"])
      usage = extract_usage(body)
      with {:ok, parsed} <- Jason.decode(content) do
        {:ok, parsed, usage}
      end

    {:ok, %{status: 402}} ->
      {:error, :provider_budget_exceeded}

    {:ok, %{status: 429}} ->
      {:error, :rate_limited}

    {:ok, %{status: status, body: body}} ->
      {:error, {:openrouter_error, status, body}}

    {:error, reason} ->
      {:error, {:http_error, reason}}
  end
end

defp extract_usage(%{"usage" => usage}) do
  %{
    prompt_tokens: usage["prompt_tokens"],
    completion_tokens: usage["completion_tokens"],
    cost_usd: usage["cost"] || 0.0
  }
end
defp extract_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: 0.0}
```

**`generate_plan/1`:**
```elixir
def generate_plan(constraints) do
  {system, user} = Scullion.LLM.Prompts.plan_weekly(constraints)
  with {:ok, json, usage} <- chat(system, user) do
    {:ok, json, usage}
  end
end
```

**`generate_prep_guide/1`:**
```elixir
def generate_prep_guide(plan) do
  {system, user} = Scullion.LLM.Prompts.prep_guide(plan)
  with {:ok, json, usage} <- chat(system, user) do
    {:ok, json, usage}
  end
end
```

---

## SpendGuard

### `lib/scullion/spend_guard.ex` (new)

Gates before calls using a monthly budget. Logs after calls using real cost from OpenRouter.

```elixir
defmodule Scullion.SpendGuard do
  @monthly_limit_usd 20.0

  def allow?(feature, estimated_tokens \\ 50_000) do
    with :ok <- budget_ok?(estimated_tokens),
         :ok <- cooldown_ok?(feature) do
      :ok
    end
  end

  def log_usage(feature, usage) do
    Scullion.Costs.log_llm_usage(%{
      feature: to_string(feature),
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      cost_usd: usage.cost_usd
    })
  end

  defp budget_ok?(estimated_tokens) do
    spent = Scullion.Costs.llm_spend_this_month()
    # Rough estimate: $4.176 / 1M tokens (haiku pricing), used only for pre-call gate
    estimated_cost = estimated_tokens * 4.176 / 1_000_000
    if spent + estimated_cost > @monthly_limit_usd do
      {:error, :budget_exceeded}
    else
      :ok
    end
  end

  # Prevent hammering: same feature can't run more than once per minute
  defp cooldown_ok?(feature) do
    last = Scullion.Costs.last_llm_call(feature)
    if last && DateTime.diff(DateTime.utc_now(), last.inserted_at, :second) < 60 do
      {:error, :cooldown}
    else
      :ok
    end
  end
end
```

---

## LLM Usage logging

### Migration `priv/repo/migrations/015_create_llm_usage.exs` (new)

```sql
CREATE TABLE llm_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  feature TEXT NOT NULL,
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  cost_usd REAL NOT NULL DEFAULT 0.0,
  inserted_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### `lib/scullion/costs/llm_usage.ex` (new Ecto schema)

```elixir
defmodule Scullion.Costs.LLMUsage do
  use Ecto.Schema

  schema "llm_usage" do
    field :feature, :string
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :cost_usd, :float
    timestamps(updated_at: false)
  end
end
```

### `lib/scullion/costs.ex` (new — or extend if it exists)

Costs context is Phase 7, but SpendGuard needs two queries now. Create a minimal
`Costs` module in Phase 5 with only what SpendGuard needs:

```elixir
defmodule Scullion.Costs do
  alias Scullion.{Repo, Costs.LLMUsage}
  import Ecto.Query

  def log_llm_usage(attrs) do
    %LLMUsage{} |> LLMUsage.changeset(attrs) |> Repo.insert()
  end

  def llm_spend_this_month do
    month_start = Date.beginning_of_month(Date.utc_today())
    Repo.one(
      from u in LLMUsage,
        where: u.inserted_at >= ^NaiveDateTime.new!(month_start, ~T[00:00:00]),
        select: coalesce(sum(u.cost_usd), 0.0)
    )
  end

  def last_llm_call(feature) do
    Repo.one(
      from u in LLMUsage,
        where: u.feature == ^to_string(feature),
        order_by: [desc: u.inserted_at],
        limit: 1
    )
  end
end
```

Phase 7 will expand this module with receipt/dining-out functions. No conflict.

---

## Handler integration (SpendGuard wrapping LLM calls)

### `lib/scullion/handlers/planning_handler.ex` — `generate_plan/3`

```elixir
@llm Application.compile_env(:scullion, :llm_client)

def generate_plan(plan_id, week_start, opts \\ []) do
  mode = Keyword.get(opts, :mode, :from_catalog)

  with :ok <- SpendGuard.allow?(:generate_plan),
       {:ok, state} <- EventStore.load(plan_id, Decider) do
    context = build_plan_context(state, week_start, mode)

    with {:ok, llm_result, usage} <- @llm.generate_plan(context),
         :ok <- SpendGuard.log_usage(:generate_plan, usage),
         {:ok, slots} <- parse_llm_slots(llm_result, mode),
         command = %Commands.GeneratePlan{week_start: week_start, slots: slots},
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(plan_id, events) do
      PubSub.broadcast(@pubsub, @topic, {:events, events})
      {:ok, events}
    end
  end
end
```

`build_plan_context/3` produces a compact map per FEAT_PROMPT_ENGINEERING.md:
- Recipes as summaries: `id | title | top-3-ingredients | time | tags` — no instructions
- Pantry: `[]` (Phase 8)
- Deals: `[]` (Phase 6)
- Recent recipes: `[]` (tracking not wired yet)
- Pins: from `state.pins`
- Mode: `:from_catalog`

`parse_llm_slots/2` converts the JSON `"days"` array into
`%{"slot_key" => %{recipe_id: integer, servings: integer}}`.
For `:from_catalog` mode, `recipe_id` must be an integer from the catalog —
if the LLM returns an unknown ID, skip that slot and log a warning.

### `lib/scullion/handlers/prep_handler.ex` (new)

```elixir
defmodule Scullion.Handlers.PrepHandler do
  alias Scullion.{Handlers.PlanningHandler, Prep, Recipes, SpendGuard}

  @llm Application.compile_env(:scullion, :llm_client)

  def generate_guide(plan_id, week_start) do
    with :ok <- SpendGuard.allow?(:generate_prep_guide),
         {:ok, plan_state} <- PlanningHandler.load_plan(plan_id) do
      plan_for_prompt = build_plan_for_prompt(plan_state, week_start)

      with {:ok, guide_data, usage} <- @llm.generate_prep_guide(plan_for_prompt),
           :ok <- SpendGuard.log_usage(:generate_prep_guide, usage) do
        attrs = Map.put(guide_data, "week_start", week_start)
        Prep.save_guide(attrs)
      end
    end
  end

  defp build_plan_for_prompt(plan_state, week_start) do
    days =
      Enum.map(plan_state.slots, fn {slot_key, slot} ->
        recipe = if slot.recipe_id, do: Recipes.get!(slot.recipe_id), else: nil
        %{slot_key: slot_key, recipe_title: recipe && recipe.title, servings: slot.servings}
      end)

    %{week_start: week_start, days: days}
  end
end
```

---

## Prompt rendering

### `lib/scullion/llm/prompts.ex` (new)

Pure module — renders EEx templates, returns `{system, user}` tuples.
Applies the token-minimising strategy from FEAT_PROMPT_ENGINEERING.md:
recipes as compact one-liners, no prose, IDs for output.

```elixir
defmodule Scullion.LLM.Prompts do
  @prompts_dir Path.join(:code.priv_dir(:scullion), "llm/prompts")

  def plan_weekly(constraints) do
    system = plan_weekly_system()
    user = render("plan_weekly.eex", constraints)
    {system, user}
  end

  def prep_guide(plan) do
    system = prep_guide_system()
    user = render("prep_guide.eex", plan)
    {system, user}
  end

  defp plan_weekly_system do
    """
    You are a meal planner. Think like a prep cook.
    Goal: assign recipes to meal slots for the week.
    Principles:
    - Batch cook early in the week; cascade leftovers into later meals
    - Prefer ingredient reuse over variety
    - Respect pinned slots as hard constraints
    - Prefer pantry items and deals when available
    - Weeknight slots need recipes ≤45 min total time
    Respond with a JSON object only. No prose.
    """
  end

  defp prep_guide_system do
    """
    You are a sous chef. Generate a Sunday prep session guide for the week's meals.
    Respond with a JSON object only. No prose.
    """
  end

  defp render(template, assigns) do
    path = Path.join(@prompts_dir, template)
    EEx.eval_file(path, assigns: Map.to_list(assigns))
  end
end
```

Templates live under `priv/llm/prompts/` — runtime data, not compiled Elixir.

---

## Prompt templates

### `priv/llm/prompts/plan_weekly.eex`

Compact format per FEAT_PROMPT_ENGINEERING.md — no recipe instructions, no prose.

```
RECIPES (id | name | key ingredients | time | tags):
<%= for r <- @recipes do %>
<%= r.id %> | <%= r.title %> | <%= Enum.map_join(Enum.take(r.key_ingredients, 3), ", ", & &1) %> | <%= r.total_time_minutes %>m | <%= Enum.join(r.tags, " ") %>
<% end %>

SLOTS TO PLAN:
<%= Enum.join(@slot_keys, " ") %>

PINNED (hard constraints):
<%= for {slot_key, pin} <- @pins do %><%= slot_key %>: <%= pin.type %> <%= Map.get(pin, :recipe_id, Map.get(pin, :text, "")) %>
<% end %>

PANTRY: <%= if Enum.empty?(@pantry), do: "none", else: Enum.join(@pantry, ", ") %>

DEALS: <%= if Enum.empty?(@deals), do: "none", else: Enum.join(@deals, ", ") %>

RECENTLY USED (avoid repeating): <%= if Enum.empty?(@recent_recipes), do: "none", else: Enum.join(@recent_recipes, ", ") %>

Return JSON only:
{
  "days": [
    {"slot_key": "mon_dinner", "recipe_id": 42, "servings": 4, "notes": "batch — leftovers for tue_lunch", "cascade_from": null}
  ],
  "prep_session": {"proteins": [], "bases": [], "sauces": [], "vegetables": []}
}
recipe_id must be an integer ID from the RECIPES list above.
```

### `priv/llm/prompts/prep_guide.eex`

```
WEEK'S PLAN:
<%= for slot <- @days do %>
<%= slot.slot_key %>: <%= slot.recipe_title || "empty" %> (×<%= slot.servings %>)
<% end %>

Return JSON only:
{
  "prep_session": {"proteins": ["..."], "bases": ["..."], "sauces": ["..."], "vegetables": ["..."]},
  "timeline": [
    {"step": 1, "task": "Preheat oven to 200°C", "duration_min": 5, "component": null}
  ],
  "cascade_map": {"mon_dinner": "Roast Chicken", "tue_lunch": "uses Mon chicken → Chicken Salad"},
  "storage_notes": "Chicken: fridge 3 days.",
  "daily_assembly": {"mon_dinner": "Plate chicken + veg", "tue_lunch": "Shred chicken, toss with dressing"}
}
```

---

## Prep context

### `lib/scullion/prep/prep_guide.ex` (expand schema)

Add new fields:

```elixir
schema "prep_guides" do
  field :week_start, :date
  field :instructions, :string
  field :timeline, {:array, :map}
  field :cascade_map, :map
  field :storage_notes, :string
  field :daily_assembly, :map
  field :prep_session, :map
  timestamps()
end
```

### `lib/scullion/prep.ex` (new)

```elixir
defmodule Scullion.Prep do
  alias Scullion.{Repo, Prep.PrepGuide}
  import Ecto.Query

  def save_guide(attrs) do
    %PrepGuide{}
    |> PrepGuide.changeset(attrs)
    |> Repo.insert(
         on_conflict: {:replace, [:timeline, :cascade_map, :storage_notes, :daily_assembly, :prep_session]},
         conflict_target: [:week_start]
       )
  end

  def get_guide_for_week(week_start) do
    Repo.one(from g in PrepGuide, where: g.week_start == ^week_start)
  end
end
```

---

## Migrations

### `priv/repo/migrations/015_create_llm_usage.exs` (new)

```elixir
defmodule Scullion.Repo.Migrations.CreateLLMUsage do
  use Ecto.Migration

  def change do
    create table(:llm_usage) do
      add :feature, :string, null: false
      add :prompt_tokens, :integer, default: 0
      add :completion_tokens, :integer, default: 0
      add :cost_usd, :float, default: 0.0
      timestamps(updated_at: false)
    end
  end
end
```

### `priv/repo/migrations/016_expand_prep_guides.exs` (new)

```elixir
defmodule Scullion.Repo.Migrations.ExpandPrepGuides do
  use Ecto.Migration

  def change do
    alter table(:prep_guides) do
      add :cascade_map, :text
      add :storage_notes, :text
      add :daily_assembly, :text
      add :prep_session, :text
    end
  end
end
```

---

## LiveView changes

### `lib/scullion_web/live/planner_live.ex` (enable generate button)

```elixir
def handle_event("generate_plan", _params, socket) do
  %{plan_id: plan_id, week_start: week_start} = socket.assigns
  case PlanningHandler.generate_plan(plan_id, week_start) do
    {:ok, _events} -> {:noreply, socket}
    {:error, :budget_exceeded} -> {:noreply, put_flash(socket, :error, "Monthly LLM budget reached")}
    {:error, :cooldown} -> {:noreply, put_flash(socket, :error, "Please wait a moment before generating again")}
    {:error, _} -> {:noreply, put_flash(socket, :error, "Plan generation failed")}
  end
end
```

Replace disabled button:
```heex
<button phx-click="generate_plan" class="px-3 py-1 bg-indigo-600 text-white rounded text-sm">
  Generate Plan
</button>
```

### `lib/scullion_web/live/prep_live.ex` (read first, then add generate button)

Add `handle_event("generate_guide", ...)` calling `PrepHandler.generate_guide/2`,
with same error handling pattern as above.

---

## Runtime config

### `config/runtime.exs`

```elixir
if config_env() == :prod do
  config :scullion, :openrouter_api_key, System.fetch_env!("OPENROUTER_API_KEY")
  config :scullion, :openrouter_model,
    System.get_env("OPENROUTER_MODEL", "anthropic/claude-3-5-haiku")
end
```

### `config/dev.exs`

```elixir
config :scullion, :openrouter_api_key, System.get_env("OPENROUTER_API_KEY", "dev-key")
config :scullion, :openrouter_model, System.get_env("OPENROUTER_MODEL", "anthropic/claude-3-5-haiku")
```

---

## Tests

All LLM tests use `Scullion.MockLLM` (Mox). Mock returns `{:ok, result, usage}` tuples.

### `test/scullion/handlers/planning_handler_test.exs` (extend)

```elixir
test "generate_plan calls LLM, logs usage, persists PlanGenerated" do
  MockLLM
  |> expect(:generate_plan, fn _ctx ->
    {:ok,
     %{"days" => [%{"slot_key" => "mon_dinner", "recipe_id" => nil, "servings" => 4,
                    "cascade_from" => nil, "notes" => ""}],
       "prep_session" => %{}},
     %{prompt_tokens: 1000, completion_tokens: 200, cost_usd: 0.001}}
  end)

  assert {:ok, _events} = PlanningHandler.generate_plan(plan_id(), week_start(), [])
  {:ok, state} = PlanningHandler.load_plan(plan_id())
  assert map_size(state.slots) == 1

  # usage was logged
  assert Scullion.Costs.llm_spend_this_month() > 0.0
end

test "generate_plan returns budget_exceeded when over limit" do
  # insert a fake usage row that exhausts the budget
  Scullion.Costs.log_llm_usage(%{feature: "generate_plan", prompt_tokens: 0,
                                  completion_tokens: 0, cost_usd: 20.0})
  assert {:error, :budget_exceeded} = PlanningHandler.generate_plan(plan_id(), week_start(), [])
end

test "generate_plan returns error when LLM fails" do
  MockLLM |> expect(:generate_plan, fn _ -> {:error, :timeout} end)
  assert {:error, :timeout} = PlanningHandler.generate_plan(plan_id(), week_start(), [])
end

test "generate_plan broadcasts PlanGenerated" do
  MockLLM
  |> expect(:generate_plan, fn _ ->
    {:ok, %{"days" => [], "prep_session" => %{}},
     %{prompt_tokens: 0, completion_tokens: 0, cost_usd: 0.0}}
  end)
  PlanningHandler.generate_plan(plan_id(), week_start(), [])
  assert_receive {:events, [%Scullion.Planning.Events.PlanGenerated{}]}
end
```

### `test/scullion/handlers/prep_handler_test.exs` (new)

```elixir
test "generate_guide calls LLM and persists prep guide" do
  MockLLM
  |> expect(:generate_prep_guide, fn _plan ->
    {:ok,
     %{"timeline" => [%{"step" => 1, "task" => "Preheat oven", "duration_min" => 5}],
       "cascade_map" => %{"mon_dinner" => "Roast Chicken"},
       "storage_notes" => "Chicken: 3 days",
       "daily_assembly" => %{},
       "prep_session" => %{"proteins" => ["chicken"]}},
     %{prompt_tokens: 500, completion_tokens: 100, cost_usd: 0.0005}}
  end)

  assert {:ok, guide} = PrepHandler.generate_guide(plan_id(), week_start())
  assert guide.week_start == week_start()
  assert length(guide.timeline) == 1
end

test "generate_guide returns error when LLM fails" do
  MockLLM |> expect(:generate_prep_guide, fn _ -> {:error, :timeout} end)
  assert {:error, :timeout} = PrepHandler.generate_guide(plan_id(), week_start())
end
```

### `test/scullion/spend_guard_test.exs` (new, `async: false`)

```elixir
test "allow? returns :ok when under budget" do
  assert :ok = SpendGuard.allow?(:generate_plan)
end

test "allow? returns {:error, :budget_exceeded} when over monthly limit" do
  Scullion.Costs.log_llm_usage(%{feature: "x", prompt_tokens: 0,
                                  completion_tokens: 0, cost_usd: 20.0})
  assert {:error, :budget_exceeded} = SpendGuard.allow?(:generate_plan)
end

test "allow? returns {:error, :cooldown} when called twice within 60s" do
  Scullion.Costs.log_llm_usage(%{feature: "generate_plan", prompt_tokens: 0,
                                  completion_tokens: 0, cost_usd: 0.01})
  assert {:error, :cooldown} = SpendGuard.allow?(:generate_plan)
end
```

### `test/scullion/adapters/open_router_test.exs` (new — integration only)

```elixir
@moduletag :integration

test "generate_plan parses real OpenRouter response" do
  constraints = %{recipes: [], slot_keys: ["mon_dinner"], pins: %{}, pantry: [],
                  deals: [], recent_recipes: []}
  assert {:ok, result, usage} = Scullion.Adapters.OpenRouter.generate_plan(constraints)
  assert Map.has_key?(result, "days")
  assert is_float(usage.cost_usd)
end
```

Run with: `mix test --include integration`

---

## Implementation order

1. `lib/scullion/llm.ex` — behaviour (unblocks compile)
2. `lib/scullion/http.ex` — behaviour
3. `priv/repo/migrations/015_create_llm_usage.exs`
4. `priv/repo/migrations/016_expand_prep_guides.exs`
5. `lib/scullion/costs/llm_usage.ex` — Ecto schema
6. `lib/scullion/costs.ex` — minimal Costs API (3 functions for SpendGuard)
7. `lib/scullion/spend_guard.ex`
8. `priv/llm/prompts/plan_weekly.eex`
9. `priv/llm/prompts/prep_guide.eex`
10. `lib/scullion/llm/prompts.ex`
11. `lib/scullion/adapters/open_router.ex` — implement `generate_plan/1` + `generate_prep_guide/1`
12. `lib/scullion/prep/prep_guide.ex` — expand schema
13. `lib/scullion/prep.ex` — `save_guide/1` + `get_guide_for_week/1`
14. `lib/scullion/handlers/planning_handler.ex` — add `generate_plan/3`
15. `lib/scullion/handlers/prep_handler.ex` — new handler
16. `lib/scullion_web/live/planner_live.ex` — enable generate button + error flash
17. `lib/scullion_web/live/prep_live.ex` — add generate guide button
18. `config/dev.exs` + `config/runtime.exs` — OpenRouter key config
19. Tests: `planning_handler_test.exs` additions, `prep_handler_test.exs`,
    `spend_guard_test.exs`, `open_router_test.exs`
20. `mix ecto.migrate && mix compile --warnings-as-errors && mix test`

---

## Constraints & decisions

- **LLM callback return shape is `{:ok, result, usage}`** across all callbacks and mocks.
  This is a breaking change from the stub (was `{:ok, result}`) — the mock must be updated too.
- **OpenRouter returns `cost` directly.** No token price math needed. `extract_usage/1`
  reads `usage["cost"]` from the response body.
- **SpendGuard monthly limit is `$20.00`** (hardcoded). An env-configurable limit is Phase 8+.
- **Cooldown is 60 seconds** between calls for the same feature — prevents UI double-taps.
- **`Costs` module is minimal in Phase 5.** Only three functions needed by SpendGuard.
  Phase 7 adds receipt/dining-out. No conflict.
- **`generate_plan` mode is `:from_catalog` only.** `:generate_new` and `:mixed` deferred.
- **Pantry and deals context is empty.** Phase 8 and 6 respectively — pass `[]`.
- **`last_used_at` not tracked yet.** `recent_recipes` is empty for now.
- **JSON mode `response_format: json_object`** required. Some models don't support it —
  system prompt instructs "Respond with JSON only" as belt-and-suspenders.
- **Model configurable via env.** Default `anthropic/claude-3-5-haiku`.
- **Integration tests skip by default.** Tagged `@tag :integration`.
- **Prompts in `priv/llm/prompts/`.** Runtime data, not compiled. `EEx.eval_file/2` at runtime.
- **Token-minimal prompts.** Recipes as compact one-liners (id|name|ingredients|time|tags),
  no instructions, no prose. Deals and pantry as flat keyword lists. IDs in output, not names.
  Per FEAT_PROMPT_ENGINEERING.md.
- **No macros.** Evaluate repetition after Phase 5 completion.
