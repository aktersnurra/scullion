# Phase 7 — Cost Tracking

## Overview

Implement food cost tracking: receipt logging (manual + LLM OCR), dining out logging, and analytics queries. The `Costs` context already exists as stubs. The schemas exist (no changesets). The migrations are missing.

### What exists (stubs / skeleton)

- `lib/scullion/costs.ex` — `log_receipt/1`, `log_dining_out/1`, `weekly_summary/1`, `monthly_summary/2`, `cost_per_meal/1` all return `{:error, :not_implemented}`; `log_llm_usage/1` and spend-guard functions are **already implemented** — do not touch
- `lib/scullion/costs/receipt.ex` — schema exists, no changeset, no `belongs_to`/`has_many`
- `lib/scullion/costs/line_item.ex` — schema exists, bare `receipt_id` integer field (not a proper `belongs_to`)
- `lib/scullion/costs/dining_out.ex` — schema exists, no changeset
- `lib/scullion/handlers/costs_handler.ex` — `parse_and_log_receipt/2` and `log_dining_out/2` are stubs
- `lib/scullion_web/live/cost_live.ex` — renders `<div>Costs</div>`
- `test/scullion/costs_test.exs` — empty DataCase shell
- `lib/scullion/adapters/open_router.ex` — `parse_receipt_image/1` returns `{:error, :not_implemented}`
- `lib/scullion/llm.ex` — `parse_receipt_image/1` callback signature: `{:ok, [map()], map()} | {:error, term()}` (returns line_items + usage metadata)

### What is missing

- Migrations: `receipts`, `line_items`, `dining_out` tables
- Changesets on `Receipt`, `LineItem`, `DiningOut`
- `belongs_to`/`has_many` associations on schemas
- `Costs` public API implementation
- `CostsHandler` implementation (receipt OCR + manual log)
- `parse_receipt_image/1` in `OpenRouter` adapter + EEx prompt template
- `CostLive` LiveView implementation
- Tests: `costs_test.exs`, `costs_handler_test.exs`

---

## Migrations

### `TIMESTAMP_create_receipts.exs`

```elixir
create table(:receipts) do
  add :date, :date, null: false
  add :store_name, :string
  add :total_amount, :decimal
  add :image_path, :string
  add :user_id, references(:users, on_delete: :nothing), null: false
  timestamps()
end

create index(:receipts, [:user_id])
create index(:receipts, [:date])
```

### `TIMESTAMP_create_line_items.exs`

```elixir
create table(:line_items) do
  add :receipt_id, references(:receipts, on_delete: :delete_all), null: false
  add :product_name, :string, null: false
  add :quantity, :decimal
  add :unit_price, :decimal
  add :total_price, :decimal
  timestamps()
end

create index(:line_items, [:receipt_id])
```

### `TIMESTAMP_create_dining_out.exs`

```elixir
create table(:dining_out) do
  add :date, :date, null: false
  add :description, :string
  add :total_amount, :decimal, null: false
  add :num_people, :integer, default: 1, null: false
  add :user_id, references(:users, on_delete: :nothing), null: false
  timestamps()
end

create index(:dining_out, [:user_id])
create index(:dining_out, [:date])
```

---

## Schemas

### `lib/scullion/costs/receipt.ex`

Add `import Ecto.Changeset`, `belongs_to :user`, `has_many :line_items`, and `changeset/2` validating `:date, :user_id`.

### `lib/scullion/costs/line_item.ex`

Replace bare `receipt_id` integer with `belongs_to :receipt`. Add `changeset/2` validating `:receipt_id, :product_name`.

### `lib/scullion/costs/dining_out.ex`

Add `import Ecto.Changeset`, `belongs_to :user`, and `changeset/2` validating `:date, :total_amount, :user_id`.

---

## `lib/scullion/costs.ex`

Keep existing `log_llm_usage/1`, `llm_spend_this_month/0`, `last_llm_call/1` untouched.

Implement the five stub functions:

### `log_receipt/1`

Accepts `%{date, store_name, total_amount, image_path, user_id, line_items: [map()]}`.

```elixir
def log_receipt(attrs) do
  line_items = Map.get(attrs, :line_items, [])
  attrs = Map.delete(attrs, :line_items)

  Repo.transaction(fn ->
    with {:ok, receipt} <- %Receipt{} |> Receipt.changeset(attrs) |> Repo.insert() do
      Enum.each(line_items, fn item ->
        %LineItem{}
        |> LineItem.changeset(Map.put(item, :receipt_id, receipt.id))
        |> Repo.insert!()
      end)
      receipt
    end
  end)
end
```

### `log_dining_out/1`

Simple insert:

```elixir
def log_dining_out(attrs) do
  %DiningOut{} |> DiningOut.changeset(attrs) |> Repo.insert()
end
```

### `weekly_summary/1`

Accepts `week_start :: Date.t()`. Returns `%{grocery_total, dining_total, total}`.

```elixir
def weekly_summary(week_start) do
  week_end = Date.add(week_start, 6)

  grocery = Repo.one(from r in Receipt,
    where: r.date >= ^week_start and r.date <= ^week_end,
    select: coalesce(sum(r.total_amount), 0))

  dining = Repo.one(from d in DiningOut,
    where: d.date >= ^week_start and d.date <= ^week_end,
    select: coalesce(sum(d.total_amount), 0))

  {:ok, %{grocery_total: grocery, dining_total: dining, total: Decimal.add(grocery, dining)}}
end
```

### `monthly_summary/2`

Accepts `year :: integer(), month :: integer()`. Returns `%{grocery_total, dining_total, total, receipt_count, dining_count}`.

```elixir
def monthly_summary(year, month) do
  {:ok, month_start} = Date.new(year, month, 1)
  month_end = Date.end_of_month(month_start)

  grocery = Repo.one(from r in Receipt,
    where: r.date >= ^month_start and r.date <= ^month_end,
    select: coalesce(sum(r.total_amount), 0))

  receipt_count = Repo.one(from r in Receipt,
    where: r.date >= ^month_start and r.date <= ^month_end,
    select: count(r.id))

  dining = Repo.one(from d in DiningOut,
    where: d.date >= ^month_start and d.date <= ^month_end,
    select: coalesce(sum(d.total_amount), 0))

  dining_count = Repo.one(from d in DiningOut,
    where: d.date >= ^month_start and d.date <= ^month_end,
    select: count(d.id))

  {:ok, %{
    grocery_total: grocery,
    dining_total: dining,
    total: Decimal.add(grocery, dining),
    receipt_count: receipt_count,
    dining_count: dining_count
  }}
end
```

### `cost_per_meal/1`

Accepts `%{week_start: Date.t(), meal_count: integer()}`. Divides week grocery total by meal count.

```elixir
def cost_per_meal(%{week_start: week_start, meal_count: meal_count}) when meal_count > 0 do
  {:ok, %{grocery_total: total}} = weekly_summary(week_start)
  {:ok, Decimal.div(total, meal_count)}
end
def cost_per_meal(_), do: {:error, :invalid_period}
```

---

## `lib/scullion/handlers/costs_handler.ex`

### `parse_and_log_receipt/2`

Calls `@llm.parse_receipt_image/1` → returns `{:ok, line_items, _usage}` → logs receipt. Image is saved to `priv/static/uploads/receipts/` before the LLM call.

```elixir
def parse_and_log_receipt(image_binary, user_id) do
  image_path = store_image(image_binary)

  with {:ok, line_items, _usage} <- @llm.parse_receipt_image(image_binary) do
    total = line_items |> Enum.map(& &1.total_price || Decimal.new(0)) |> Enum.reduce(&Decimal.add/2)

    Scullion.Costs.log_receipt(%{
      date: Date.utc_today(),
      image_path: image_path,
      total_amount: total,
      user_id: user_id,
      line_items: line_items
    })
  end
end

defp store_image(binary) do
  filename = "#{System.unique_integer([:positive])}.jpg"
  path = Path.join([:code.priv_dir(:scullion), "static", "uploads", "receipts", filename])
  File.mkdir_p!(Path.dirname(path))
  File.write!(path, binary)
  "/uploads/receipts/#{filename}"
end
```

### `log_dining_out/2`

```elixir
def log_dining_out(attrs, user_id) do
  Scullion.Costs.log_dining_out(Map.put(attrs, :user_id, user_id))
end
```

---

## `lib/scullion/llm/prompts/parse_receipt.eex`

New EEx template. The adapter renders this and sends to OpenRouter with vision capability.

The system prompt instructs the model to extract line items from a receipt image as JSON:

```
System: You are a receipt parser. Extract each line item from the receipt image.
Return a JSON object: {"line_items": [{"product_name": "...", "quantity": 1, "unit_price": 9.90, "total_price": 9.90}], "store_name": "...", "total": 0.00}.
Use null for missing values. All amounts in SEK as decimal numbers.
```

### `lib/scullion/adapters/open_router.ex` — implement `parse_receipt_image/1`

Encode the image as base64, send as a vision message to a vision-capable model (e.g., `google/gemini-flash-1.5`). Parse the JSON response into line_item maps.

```elixir
def parse_receipt_image(image_binary) do
  b64 = Base.encode64(image_binary)
  system = EEx.eval_file(prompt_path("parse_receipt.eex"), [])
  # send as vision message; parse JSON response
  chat_vision(system, b64)
end
```

The `chat_vision/2` private function sends a multipart user message with `image_url` type pointing to the base64 data URI.

---

## `lib/scullion_web/live/cost_live.ex`

Three tabs: **Overview**, **Receipts**, **Dining Out**.

### `mount/3`
Load this month's summary. Assign `view: :overview`, `receipts: []`, `dining_entries: []`, `summary: nil`.

### Handles
- `"switch_tab"` — switches `view`
- `"log_dining_out"` — form submit with `{date, description, total_amount, num_people}` → `CostsHandler.log_dining_out/2`
- `"upload_receipt"` — file upload → `CostsHandler.parse_and_log_receipt/2` (member only)
- `"save_manual_receipt"` — form submit with `{date, store_name, total_amount}` + line items → `Costs.log_receipt/1`

### Overview tab
Display this month's `monthly_summary/2`: grocery total, dining total, combined total, counts.

### Receipts tab
List receipts (date, store, total). Show line items on click. Upload form (photo) for LLM parsing.
Manual entry form as fallback: date + store + line items (add/remove rows).

### Dining Out tab
List dining out entries (date, description, amount, people, per-person cost).
Form to log a new entry.

### Role guards
- Receipt upload (LLM): member and admin only
- Manual entry: member and admin only
- kiosk: read-only, no forms shown

---

## Tests

### `test/scullion/costs_test.exs`

Use `async: false`, sandbox checkout. Tests:

1. `log_receipt/1` inserts receipt and line items
2. `log_receipt/1` returns error on invalid attrs (missing required fields)
3. `log_dining_out/1` inserts entry
4. `weekly_summary/1` sums groceries and dining for the week
5. `weekly_summary/1` returns zeros for an empty week
6. `monthly_summary/2` sums across month boundaries correctly
7. `cost_per_meal/1` divides grocery total by meal count
8. `cost_per_meal/1` returns error for zero meal_count

### `test/scullion/handlers/costs_handler_test.exs`

Use `async: false`, Mox MockLLM, sandbox checkout. Tests:

1. `parse_and_log_receipt/2` calls LLM, stores image, inserts receipt — mock returns `{:ok, [line_item_map], %{}}`
2. `parse_and_log_receipt/2` returns LLM error unchanged when LLM fails
3. `log_dining_out/2` delegates to `Costs.log_dining_out/1`

---

## Implementation order

1. Migrations: `create_receipts`, `create_line_items`, `create_dining_out` — run `mix ecto.migrate`
2. Update `receipt.ex`, `line_item.ex`, `dining_out.ex` — add associations and changesets
3. Implement `Costs.log_receipt/1` and `Costs.log_dining_out/1`
4. Implement `Costs.weekly_summary/1`, `monthly_summary/2`, `cost_per_meal/1`
5. Write `lib/scullion/llm/prompts/parse_receipt.eex`
6. Implement `parse_receipt_image/1` in `OpenRouter` adapter
7. Implement `CostsHandler.parse_and_log_receipt/2`
8. Implement `CostLive` LiveView (three tabs)
9. Tests: `costs_test.exs`, `costs_handler_test.exs`
10. `mix compile --warnings-as-errors && mix test`

---

## Constraints & decisions

- **`log_llm_usage/1`, `llm_spend_this_month/0`, `last_llm_call/1` are untouched.** They are already implemented in `costs.ex`. Phase 7 only adds the five stub functions below them.
- **LLM receipt parsing is best-effort.** The `parse_receipt_image/1` callback returns `{:ok, line_items, usage_map}` per the existing `Scullion.LLM` behaviour signature — three-element tuple, not two.
- **Manual entry is the fallback, not the primary flow.** Receipt photo upload → LLM is the happy path. Manual form is shown for member/admin but not required to be feature-complete for kiosk.
- **Image storage is local.** Files saved to `priv/static/uploads/receipts/`. No cloud storage in this phase.
- **`total_amount` on Receipt is derived from line items** when coming from LLM parse (sum of `total_price`). For manual entry, the user enters it directly.
- **No pagination.** Lists are unbounded for now — this is a two-user system.
- **`date.ex` doesn't exist in stdlib for `end_of_month`.** Use `Date.end_of_month/1` (available in Elixir 1.11+).
- **MockLLM already exists** in `test/support/mocks.ex` as `Scullion.MockLLM` — verify before writing handler tests.
