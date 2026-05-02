# Phase 6 — Deals Scraping

## Overview

Implement the deals pipeline:

1. **Deals context** — `Scullion.Deals` public API: `upsert_deals`, `list_current`, `clear_expired`
2. **ICA parser** — pure HTML parsing of `ica.se/erbjudanden/` pages
3. **Coop parser** — pure HTML parsing (stub initially, marked not_implemented)
4. **DealsHandler** — orchestrates HTTP fetch → parse → upsert; ad-hoc URL scraping
5. **Migrations** — `deals` and `store_configs` tables
6. **Deals LiveView** — display current deals; manual URL scrape trigger (admin)
7. **Quantum scheduler** — Saturday 08:00 scrape job wired up
8. **LLM feed** — `Deals.list_current()` fed into `PlanningHandler.generate_plan/3` context

Stubs from Phase 1 skeleton exist. Tables are missing — migrations needed first.

---

## What already exists

**Stubs (need implementation):**
- `lib/scullion/deals.ex` — all three functions return `{:error, :not_implemented}` or `[]`
- `lib/scullion/deals/deal.ex` — Ecto schema, no changeset
- `lib/scullion/deals/store_config.ex` — Ecto schema, no changeset
- `lib/scullion/deals/parsers/parser.ex` — behaviour only
- `lib/scullion/deals/parsers/ica.ex` — returns `{:error, :not_implemented}`
- `lib/scullion/deals/parsers/coop.ex` — returns `{:error, :not_implemented}`
- `lib/scullion/handlers/deals_handler.ex` — `scrape_all/0` + `scrape_store/1` wired but calls unimplemented parsers and context
- `lib/scullion_web/live/deals_live.ex` — renders `<div>Deals</div>`

**Missing (need creation):**
- `priv/repo/migrations/*_create_deals.exs`
- `priv/repo/migrations/*_create_store_configs.exs`
- `lib/scullion/scheduler.ex` — Quantum job registration

**Already wired:**
- `config :scullion, :http_client, Scullion.Adapters.ReqHTTP` (dev/prod)
- `config :scullion, :http_client, Scullion.MockHTTP` (test)
- `Scullion.Adapters.ReqHTTP` — stub returning `{:error, :not_implemented}` (implement here)

---

## Migrations

### `priv/repo/migrations/TIMESTAMP_create_deals.exs`

```elixir
create table(:deals) do
  add :store, :string, null: false
  add :store_location, :string
  add :product_name, :string, null: false
  add :brand, :string
  add :size, :string
  add :price, :decimal
  add :price_unit, :string
  add :offer_condition, :string
  add :valid_from, :date
  add :valid_until, :date
  add :source, :string, null: false, default: "scraped"
  timestamps()
end

create index(:deals, [:store, :valid_until])
```

### `priv/repo/migrations/TIMESTAMP_create_store_configs.exs`

```elixir
create table(:store_configs) do
  add :name, :string, null: false
  add :chain, :string, null: false
  add :store_id, :string
  add :url, :string
  add :scrape_enabled, :boolean, default: false, null: false
  timestamps()
end
```

---

## Deals context

### `lib/scullion/deals/deal.ex` (add changeset)

```elixir
defmodule Scullion.Deals.Deal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deals" do
    field :store, :string
    field :store_location, :string
    field :product_name, :string
    field :brand, :string
    field :size, :string
    field :price, :decimal
    field :price_unit, :string
    field :offer_condition, :string
    field :valid_from, :date
    field :valid_until, :date
    field :source, Ecto.Enum, values: [:scraped, :vision, :manual]
    timestamps()
  end

  def changeset(deal, attrs) do
    deal
    |> cast(attrs, [:store, :store_location, :product_name, :brand, :size,
                    :price, :price_unit, :offer_condition, :valid_from, :valid_until, :source])
    |> validate_required([:store, :product_name, :source])
  end
end
```

### `lib/scullion/deals/store_config.ex` (add changeset)

```elixir
defmodule Scullion.Deals.StoreConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "store_configs" do
    field :name, :string
    field :chain, Ecto.Enum, values: [:ica, :coop]
    field :store_id, :string
    field :url, :string
    field :scrape_enabled, :boolean, default: false
    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:name, :chain, :store_id, :url, :scrape_enabled])
    |> validate_required([:name, :chain])
  end
end
```

### `lib/scullion/deals.ex` (implement)

```elixir
defmodule Scullion.Deals do
  alias Scullion.{Repo, Deals.Deal}
  import Ecto.Query

  @spec upsert_deals([map()]) :: {:ok, integer()} | {:error, term()}
  def upsert_deals(deals) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    rows = Enum.map(deals, fn d ->
      d
      |> Map.put_new(:source, :scraped)
      |> Map.merge(%{inserted_at: now, updated_at: now})
    end)

    {count, _} = Repo.insert_all(Deal, rows, on_conflict: :nothing)
    {:ok, count}
  end

  @spec list_current() :: [Deal.t()]
  def list_current do
    today = Date.utc_today()
    Repo.all(from d in Deal, where: is_nil(d.valid_until) or d.valid_until >= ^today)
  end

  @spec clear_expired() :: :ok
  def clear_expired do
    today = Date.utc_today()
    Repo.delete_all(from d in Deal, where: not is_nil(d.valid_until) and d.valid_until < ^today)
    :ok
  end
end
```

---

## HTTP adapter

### `lib/scullion/adapters/req_http.ex` (implement)

```elixir
defmodule Scullion.Adapters.ReqHTTP do
  @behaviour Scullion.HTTP

  @impl Scullion.HTTP
  def fetch(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, {:req_error, reason}}
    end
  end
end
```

---

## Parser behaviour + ICA implementation

### `lib/scullion/deals/parsers/parser.ex` (unchanged)

Behaviour stays as-is.

### `lib/scullion/deals/parsers/ica.ex` (implement)

ICA.se deal pages at `https://www.ica.se/erbjudanden/{store-slug}-{store-id}/` use
structured HTML. Each deal is in a repeating element with product name, brand, price,
offer condition, and valid dates.

The parser is **pure** — HTML string in, `[deal_attrs]` out. No HTTP, no Ecto.

```elixir
defmodule Scullion.Deals.Parsers.ICA do
  @behaviour Scullion.Deals.Parsers.Parser

  @impl Scullion.Deals.Parsers.Parser
  def parse(html) do
    # Use Floki to extract deal cards from ICA HTML structure.
    # ICA.se uses structured HTML with data attributes and consistent class names.
    # Each offer card contains: product name, brand, size/unit, price, offer condition, dates.
    deals =
      Floki.parse_document!(html)
      |> Floki.find("[data-testid='offer-card'], .offer-card, .product-offer")
      |> Enum.map(&extract_deal/1)
      |> Enum.reject(&is_nil/1)

    {:ok, deals}
  end

  defp extract_deal(card) do
    product_name = card |> Floki.find("[data-testid='product-name'], .product-name") |> Floki.text() |> String.trim()
    price_text = card |> Floki.find("[data-testid='price'], .price") |> Floki.text() |> String.trim()

    if product_name == "" do
      nil
    else
      %{
        store: "ica",
        product_name: product_name,
        brand: extract_text(card, "[data-testid='brand'], .brand"),
        size: extract_text(card, "[data-testid='comparative-price'], .comparative-price"),
        price: parse_price(price_text),
        price_unit: extract_price_unit(price_text),
        offer_condition: extract_text(card, "[data-testid='splash'], .splash, .offer-condition"),
        source: :scraped
      }
    end
  end

  defp extract_text(card, selector) do
    card |> Floki.find(selector) |> Floki.text() |> String.trim() |> nilify()
  end

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp parse_price(text) do
    case Regex.run(~r/(\d+[,.]?\d*)/, text) do
      [_, digits] -> digits |> String.replace(",", ".") |> Decimal.new()
      _ -> nil
    end
  end

  defp extract_price_unit(text) do
    cond do
      String.contains?(text, "/kg") -> "kr/kg"
      String.contains?(text, "/st") -> "kr/st"
      String.contains?(text, "/l") -> "kr/l"
      true -> nil
    end
  end
end
```

**Note:** ICA's HTML structure may require adjustment after first real fetch. The selectors
above are based on common patterns — verify against a real page before claiming correctness.
The selectors are isolated in `extract_deal/1` so they're easy to update.

### `lib/scullion/deals/parsers/coop.ex` (leave as stub)

Coop parsing is deferred — leave `{:error, :not_implemented}`. This is documented
behaviour, not an oversight.

---

## DealsHandler

### `lib/scullion/handlers/deals_handler.ex` (implement fully)

```elixir
defmodule Scullion.Handlers.DealsHandler do
  alias Scullion.{Deals, Deals.StoreConfig, Repo}

  @http Application.compile_env(:scullion, :http_client)

  @spec scrape_all() :: :ok
  def scrape_all do
    StoreConfig
    |> Repo.all()
    |> Enum.filter(& &1.scrape_enabled)
    |> Enum.each(&scrape_store/1)

    :ok
  end

  @spec scrape_url(String.t(), atom()) :: {:ok, integer()} | {:error, term()}
  def scrape_url(url, chain) do
    parser = parser_for(chain)

    with {:ok, html} <- @http.fetch(url),
         {:ok, deals} <- parser.parse(html) do
      Deals.upsert_deals(deals)
    end
  end

  defp scrape_store(store_config) do
    scrape_url(store_config.url, store_config.chain)
  end

  defp parser_for(:ica), do: Scullion.Deals.Parsers.ICA
  defp parser_for(:coop), do: Scullion.Deals.Parsers.Coop
end
```

---

## Quantum scheduler

### `lib/scullion/scheduler.ex` (new)

```elixir
defmodule Scullion.Scheduler do
  use Quantum, otp_app: :scullion
end
```

### `config/config.exs` (add Quantum config)

```elixir
config :scullion, Scullion.Scheduler,
  jobs: [
    {"0 8 * * 6", {Scullion.Handlers.DealsHandler, :scrape_all, []}},
    {"0 18 * * 6", fn -> Scullion.Handlers.PlanningHandler.generate_plan("plan:current", Date.utc_today()) end},
    {"30 18 * * 6", fn -> Scullion.Handlers.PrepHandler.generate_guide("plan:current", Date.utc_today()) end}
  ]
```

### `lib/scullion/application.ex` (add Scheduler to supervision tree)

Add `Scullion.Scheduler` to the children list after the Repo.

---

## Feed deals into planner

### `lib/scullion/handlers/planning_handler.ex` (update `build_plan_context/3`)

Replace `deals: []` with:

```elixir
deals: Deals.list_current() |> Enum.map(fn d ->
  "#{d.product_name}#{if d.price, do: " #{d.price}kr", else: ""}"
end)
```

Add `alias Scullion.Deals` at top of module.

---

## LiveView

### `lib/scullion_web/live/deals_live.ex` (implement)

Display current deals grouped by store. Admin can trigger a manual scrape via URL entry.

```elixir
defmodule ScullionWeb.DealsLive do
  use ScullionWeb, :live_view

  alias Scullion.{Deals, Deals.StoreConfig, Repo, Handlers.DealsHandler}

  def mount(_params, _session, socket) do
    deals = Deals.list_current()
    {:ok, assign(socket, deals: deals, scrape_url: "", scrape_chain: :ica, scraping: false)}
  end

  def handle_event("scrape_url", %{"url" => url, "chain" => chain}, socket) do
    chain_atom = String.to_existing_atom(chain)
    case DealsHandler.scrape_url(url, chain_atom) do
      {:ok, count} ->
        {:noreply, socket
          |> assign(deals: Deals.list_current(), scraping: false)
          |> put_flash(:info, "Imported #{count} deals")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Scrape failed")}
    end
  end

  def handle_event("scrape_all", _params, socket) do
    DealsHandler.scrape_all()
    {:noreply, socket |> assign(deals: Deals.list_current()) |> put_flash(:info, "Scrape triggered")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-4">
      <h1 class="text-xl font-semibold mb-4">Current Deals</h1>

      <%= if @current_user && @current_user.role == :admin do %>
        <div class="mb-4 flex gap-2">
          <input type="text" placeholder="https://www.ica.se/erbjudanden/..."
                 phx-blur="update_url" name="url"
                 class="flex-1 border rounded px-2 py-1 text-sm" />
          <select name="chain" class="border rounded px-2 py-1 text-sm">
            <option value="ica">ICA</option>
            <option value="coop">Coop</option>
          </select>
          <button phx-click="scrape_all"
                  class="px-3 py-1 bg-indigo-600 text-white rounded text-sm">
            Scrape All
          </button>
        </div>
      <% end %>

      <%= if Enum.empty?(@deals) do %>
        <p class="text-gray-500 text-sm">No current deals.</p>
      <% else %>
        <ul class="divide-y">
          <%= for deal <- @deals do %>
            <li class="py-2">
              <span class="font-medium"><%= deal.product_name %></span>
              <%= if deal.brand do %><span class="text-gray-500 text-sm ml-1"><%= deal.brand %></span><% end %>
              <%= if deal.price do %>
                <span class="ml-2 text-green-700 font-semibold"><%= deal.price %> kr</span>
                <%= if deal.price_unit do %><span class="text-xs text-gray-500"><%= deal.price_unit %></span><% end %>
              <% end %>
              <%= if deal.offer_condition do %>
                <span class="ml-2 text-xs text-gray-400"><%= deal.offer_condition %></span>
              <% end %>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end
end
```

---

## Tests

### `test/scullion/deals/parsers/ica_test.exs` (replace stub test, add real fixture test)

```elixir
defmodule Scullion.Deals.Parsers.ICATest do
  use ExUnit.Case, async: true

  alias Scullion.Deals.Parsers.ICA

  @fixture_html """
  <div data-testid="offer-card">
    <span data-testid="product-name">Kycklingfilé</span>
    <span data-testid="brand">Kronfågel</span>
    <span data-testid="price">59,90/kg</span>
    <span data-testid="splash">Köp 2 betala för 1</span>
  </div>
  """

  test "parse/1 extracts deals from offer cards" do
    assert {:ok, [deal | _]} = ICA.parse(@fixture_html)
    assert deal.product_name == "Kycklingfilé"
    assert deal.brand == "Kronfågel"
    assert deal.store == "ica"
    assert deal.source == :scraped
  end

  test "parse/1 returns empty list for page with no offer cards" do
    assert {:ok, []} = ICA.parse("<html><body>No offers</body></html>")
  end

  test "parse/1 always returns :ok tuple" do
    assert {:ok, _} = ICA.parse("")
  end
end
```

### `test/scullion/deals_test.exs` (new, `async: false`)

```elixir
defmodule Scullion.DealsTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Scullion.Repo)
  end

  test "upsert_deals inserts new deals and returns count" do
    deals = [%{store: "ica", product_name: "Mjölk", source: :scraped}]
    assert {:ok, 1} = Scullion.Deals.upsert_deals(deals)
  end

  test "list_current returns deals without valid_until" do
    Scullion.Deals.upsert_deals([%{store: "ica", product_name: "Bröd", source: :scraped}])
    assert length(Scullion.Deals.list_current()) >= 1
  end

  test "list_current excludes expired deals" do
    Scullion.Deals.upsert_deals([
      %{store: "ica", product_name: "Expired", source: :scraped, valid_until: ~D[2020-01-01]}
    ])
    deals = Scullion.Deals.list_current()
    refute Enum.any?(deals, &(&1.product_name == "Expired"))
  end

  test "clear_expired removes deals past valid_until" do
    Scullion.Deals.upsert_deals([
      %{store: "ica", product_name: "OldDeal", source: :scraped, valid_until: ~D[2020-01-01]}
    ])
    Scullion.Deals.clear_expired()
    deals = Scullion.Deals.list_current()
    refute Enum.any?(deals, &(&1.product_name == "OldDeal"))
  end
end
```

### `test/scullion/handlers/deals_handler_test.exs` (new, `async: false`)

```elixir
defmodule Scullion.Handlers.DealsHandlerTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Scullion.Repo)
  end

  test "scrape_url fetches HTML and upserts deals" do
    ica_html = "<div data-testid=\"offer-card\"><span data-testid=\"product-name\">Kyckling</span></div>"

    Scullion.MockHTTP
    |> expect(:fetch, fn _url -> {:ok, ica_html} end)

    assert {:ok, _count} = Scullion.Handlers.DealsHandler.scrape_url("https://ica.se/erbjudanden/test-123/", :ica)
  end

  test "scrape_url returns error on HTTP failure" do
    Scullion.MockHTTP
    |> expect(:fetch, fn _url -> {:error, :timeout} end)

    assert {:error, :timeout} = Scullion.Handlers.DealsHandler.scrape_url("https://ica.se/", :ica)
  end
end
```

---

## Dependencies

### `mix.exs`

Add `{:floki, "~> 0.36"}` and `{:quantum, "~> 3.5"}` to deps if not already present.

---

## Implementation order

1. Check `mix.exs` — add `floki` and `quantum` if missing, run `mix deps.get`
2. `priv/repo/migrations/TIMESTAMP_create_deals.exs`
3. `priv/repo/migrations/TIMESTAMP_create_store_configs.exs`
4. `mix ecto.migrate`
5. `lib/scullion/deals/deal.ex` — add changeset
6. `lib/scullion/deals/store_config.ex` — add changeset
7. `lib/scullion/deals.ex` — implement three functions
8. `lib/scullion/adapters/req_http.ex` — implement `fetch/1`
9. `lib/scullion/deals/parsers/ica.ex` — implement with Floki
10. `lib/scullion/handlers/deals_handler.ex` — implement `scrape_url/2`, fix `scrape_all/0`
11. `lib/scullion/scheduler.ex` — new Quantum module
12. `config/config.exs` — Quantum jobs
13. `lib/scullion/application.ex` — add Scheduler to supervision tree
14. `lib/scullion/handlers/planning_handler.ex` — feed `Deals.list_current()` into context
15. `lib/scullion_web/live/deals_live.ex` — implement LiveView
16. Tests: `ica_test.exs`, `deals_test.exs`, `deals_handler_test.exs`
17. `mix compile --warnings-as-errors && mix test`

---

## Constraints & decisions

- **ICA selectors are best-effort.** ICA's HTML structure is scraped public HTML and
  may differ from the selectors above. The test uses a fixture we control; real-page
  verification requires an integration test or manual check.
- **Coop stays stubbed.** `{:error, :not_implemented}` is a documented decision, not
  a bug. Phase 7 or later adds Coop support.
- **`upsert_deals` uses `on_conflict: :nothing`** — duplicate scrapes on the same run
  don't fail and don't duplicate rows. Good enough for ephemeral deal data.
- **No LLM fallback in this phase.** `parse_deals_image/1` (vision for personalised
  ICA deals or PDF reklamblad) is Phase 8+.
- **Quantum runs in prod only** conceptually — in dev the jobs are registered but
  won't fire unless the cron time hits. Manual trigger via `DealsHandler.scrape_all/0`
  in dev.
- **`scrape_all` returns `:ok`** regardless of individual store failures. Errors are
  logged per store but don't block other stores. Failure isolation.
- **`MockHTTP` already exists** in test config — `Scullion.MockHTTP` is the Mox mock
  for `Scullion.HTTP`. Just use it.
- **No pagination on ICA pages.** Single page per store. If ICA paginates, that's
  a later concern.
- **Floki is added as a dep.** It may already be present (recipe scraping in Phase 3
  also needs it). Check before adding.
