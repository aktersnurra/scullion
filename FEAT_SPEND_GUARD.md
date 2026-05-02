---

# 🧾 Scullion Spend Guard (OpenRouter Edition)

## 🎯 What changes vs generic version

* You **still gate before calls** (using estimates)
* But you also **log exact cost after calls** (from OpenRouter response)
* Over time, your estimates become irrelevant

---

# 🧠 OpenRouter response shape (important)

OpenRouter responses typically include usage like:

```json
{
  "usage": {
    "prompt_tokens": 42000,
    "completion_tokens": 3200,
    "total_tokens": 45200
  }
}
```

Some models also include cost, otherwise you compute it.

---

# 🧱 1. LLM Adapter (critical upgrade)

Wrap OpenRouter so *every call returns usage metadata*.

```elixir
defmodule Scullion.Adapters.OpenRouter do
  @behaviour Scullion.LLM

  def generate_plan(context) do
    body = %{
      model: "openrouter/model",
      messages: build_messages(context)
    }

    with {:ok, resp} <- Req.post(url: base_url(), json: body),
         {:ok, parsed} <- decode(resp.body) do

      usage = extract_usage(parsed)

      {:ok, parsed["choices"] |> extract_content(), usage}
    end
  end

  defp extract_usage(%{"usage" => usage}) do
    %{
      input_tokens: usage["prompt_tokens"],
      output_tokens: usage["completion_tokens"]
    }
  end
end
```

👉 **Important change**:
Return `{:ok, result, usage}` everywhere

---

# 🧮 2. Centralized cost calculation

```elixir
defmodule Scullion.LLM.Cost do
  @input_price 1.392 / 1_000_000
  @output_price 2.784 / 1_000_000

  def compute(%{input_tokens: in_t, output_tokens: out_t}) do
    (in_t * @input_price) + (out_t * @output_price)
  end
end
```

---

# 🧾 3. Logging real usage (no guessing anymore)

In handler:

```elixir
with :ok <- SpendGuard.allow?(:generate_plan, 50_000),
     {:ok, result, usage} <- @llm.generate_plan(context),
     cost = Cost.compute(usage),
     :ok <- Costs.log_llm_usage(%{
       feature: "generate_plan",
       input_tokens: usage.input_tokens,
       output_tokens: usage.output_tokens,
       cost_usd: cost
     }),
     {:ok, events} <- decide_and_store(result) do

  SpendGuard.record(:generate_plan)

  {:ok, events}
end
```

---

# 🧠 4. SpendGuard (refined)

Now your guard becomes:

* **estimate before**
* **real tracking after**

```elixir
defmodule Scullion.SpendGuard do
  alias Scullion.Costs

  @monthly_limit 20.0
  @price_per_token 4.176 / 1_000_000

  def allow?(feature, estimated_tokens) do
    with :ok <- budget_ok?(estimated_tokens),
         :ok <- cooldown_ok?(feature),
         :ok <- limits_ok?(feature) do
      :ok
    end
  end

  defp budget_ok?(estimated_tokens) do
    spent = Costs.llm_spend_this_month()

    projected = spent + estimated_tokens * @price_per_token

    if projected > @monthly_limit do
      {:error, :budget_exceeded}
    else
      :ok
    end
  end
end
```

---

# 🔁 5. Optional: adaptive estimates (nice upgrade)

After a few runs, you can *learn* actual usage:

```elixir
def estimate(:generate_plan) do
  avg = Costs.avg_tokens("generate_plan")

  if avg do
    avg * 1.2  # safety margin
  else
    50_000
  end
end
```

---

# 🧨 6. Hard stop on API errors

When OpenRouter cuts you off:

Handle it explicitly:

```elixir
case @llm.generate_plan(context) do
  {:error, %{status: 402}} ->
    {:error, :provider_limit_reached}

  {:error, %{status: 429}} ->
    {:error, :rate_limited}

  other ->
    other
end
```

---

# 🧾 7. Costs table (unchanged, but now meaningful)

You now store **real money**, not guesses:

```sql
feature TEXT
input_tokens INTEGER
output_tokens INTEGER
cost_usd REAL
inserted_at TEXT
```

---

# 📊 8. What you unlock with this

Because you're using OpenRouter:

### You can now:

* See exact cost per feature:

  * “Plan generation = $0.07”
  * “Receipt parsing = $0.01”

* Identify waste:

  * prompts too big
  * output too long

* Optimize later without guessing

---

# 🧠 Subtle but important insight

Before:

> “Am I spending too much?”

After:

> “Which feature is inefficient?”

That’s a *huge* difference.

---

# ⚖️ Final architecture (clean)

```
Handler
  ↓ (estimate gate)
SpendGuard.allow?
  ↓
LLM Adapter (OpenRouter)
  ↓ (returns usage)
Cost.compute
  ↓
Costs.log_llm_usage
```

---

# 🔥 What you should NOT do

* Don’t trust provider limits alone
* Don’t skip logging usage
* Don’t pass full context blindly (this is your real cost driver)

---

# 🧾 Bottom line

With OpenRouter:

* Your guard becomes **accurate, not heuristic**
* Your costs become **observable**
* Your system becomes **tunable**

---
