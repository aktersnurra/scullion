---

# 🎯 Core idea

> Stop sending *data*. Start sending *decisions*.

Your planner doesn’t need:

* full recipes ❌
* verbose pantry lists ❌
* raw deal text ❌

It needs:

* **constraints + options + signals** ✅

---

# 🧠 Target prompt architecture (lean)

## Instead of this (typical bad version)

```text
Here are 120 recipes:
- Spaghetti Bolognese: ingredients..., instructions...
- Chicken Curry: ingredients..., instructions...
...

Pantry:
- 500g rice
- 2 onions
...

Deals:
- ICA chicken 89kr/kg valid until...
...

Generate a weekly meal plan...
```

👉 This explodes tokens.

---

## Do this instead (optimized)

### 1. System prompt (stable, reusable)

```text
You are a meal planner.

Goal:
Generate a 5-day dinner plan (Mon–Fri).

Constraints:
- Prefer meals that reuse ingredients
- Prefer meals using deals or pantry items
- Optimize for batch cooking (leftovers)

Output JSON only:
{
  "days": [
    { "day": "Mon", "recipe_id": "...", "servings": 4, "notes": "..." }
  ]
}
```

👉 Keep this **short + static**

---

### 2. Dynamic prompt (compressed inputs)

#### A. Recipes → **summaries only**

```text
RECIPES (id, tags, key ingredients, time):

r1 | spaghetti | pasta, beef, tomato | 30m
r2 | chicken_curry | chicken, coconut milk, rice | 40m
r3 | salmon_oven | salmon, potato, dill | 25m
```

👉 No instructions, no prose

---

#### B. Pantry → **deduplicated + normalized**

```text
PANTRY:

onion (2)
garlic (1)
rice (500g)
pasta (300g)
```

👉 No sentences, no units noise

---

#### C. Deals → **signal only**

```text
DEALS:

chicken (cheap)
salmon (discount)
```

👉 Don’t include prices, stores, validity text

---

#### D. History → **minimal**

```text
RECENTLY USED:

spaghetti
tacos
```

👉 Avoid repetition without sending full history

---

### 3. Final prompt

```text
Plan meals for Mon–Fri.

RECIPES:
r1 | spaghetti | pasta, beef, tomato | 30m
r2 | chicken_curry | chicken, coconut milk, rice | 40m
r3 | salmon_oven | salmon, potato, dill | 25m

PANTRY:
onion (2), garlic (1), rice (500g), pasta (300g)

DEALS:
chicken, salmon

RECENTLY USED:
spaghetti, tacos

Constraints:
- Use pantry items when possible
- Prefer deals
- Include 1–2 leftover-friendly meals

Return JSON only.
```

---

# 💥 Why this cuts ~50% (often 70%)

### You remove:

* recipe instructions (huge)
* ingredient duplication
* natural language fluff
* store/deal verbosity

### You keep:

* decision-relevant signals

---

# 📉 Token comparison (realistic)

| Approach            | Tokens  |
| ------------------- | ------- |
| Full recipe dump    | 40k–80k |
| Optimized summaries | 10k–20k |

👉 That’s your 50–75% reduction

---

# 🧩 Backend changes you need

## 1. Recipe “planner projection”

Add a function:

```elixir
def planner_summary(recipe) do
  %{
    id: recipe.id,
    title: recipe.title,
    ingredients: top_ingredients(recipe, 3),
    tags: recipe.tags,
    time: recipe.total_time
  }
end
```

---

## 2. Ingredient compression

```elixir
def compress_pantry(items) do
  items
  |> Enum.group_by(& &1.name)
  |> Enum.map(fn {name, items} ->
    total = sum_quantities(items)
    "#{name} (#{total})"
  end)
end
```

---

## 3. Deal simplification

```elixir
def simplify_deals(deals) do
  deals
  |> Enum.map(& &1.product_name)
  |> Enum.uniq()
end
```

---

# 🧠 Big win: ID-based planning

Instead of:

```json
{ "recipe": "Chicken curry with coconut milk and lime..." }
```

Use:

```json
{ "recipe_id": "r2" }
```

👉 You avoid:

* long outputs
* ambiguity
* re-parsing

---

# 🔁 Even better: 2-step planning (advanced)

If you want another **30–50% reduction later**:

### Step 1 — selection

LLM picks recipe IDs only

### Step 2 — enrichment

You fill in details server-side

---

# ⚠️ Common mistakes (don’t do these)

* Sending full ingredient lists per recipe ❌
* Sending instructions ❌
* Sending duplicate pantry + recipe overlap ❌
* Including natural language explanations ❌
* Asking for verbose output ❌

---

# 🧾 Ideal output (tight)

```json
{
  "days": [
    { "day": "Mon", "recipe_id": "r2", "servings": 6, "notes": "leftovers for Tue" },
    { "day": "Tue", "recipe_id": "r2", "servings": 2 },
    { "day": "Wed", "recipe_id": "r3", "servings": 4 }
  ]
}
```

---

# 🔥 Biggest leverage insight

You don’t need a “smart” model.

You need a **small, clean decision surface**.

---

# ⚖️ Bottom line

To cut token usage ~50%:

1. Replace recipes with **summaries**
2. Strip deals → **keywords only**
3. Normalize pantry → **deduped list**
4. Use **IDs instead of text**
5. Keep prompt brutally compact

---
