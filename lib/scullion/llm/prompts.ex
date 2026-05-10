defmodule Scullion.LLM.Prompts do
  @prompts_dir Path.join(:code.priv_dir(:scullion), "llm/prompts")

  def suggest_slot_recipe(context) do
    system = """
    You are a meal planner suggesting one recipe for a single dinner slot.
    Goal: pick the best fit from the candidate recipes given week context.
    Principles:
    - Reuse ingredients from neighboring meals
    - Prefer pantry items and current deals
    - Avoid recipes already cooked this week
    - Match the day's available time and energy
    You MUST pick a recipe_id from the provided candidate list.
    Respond ONLY with JSON: {"recipe_id": <int>, "reasoning": "<one short sentence>"}.
    """

    user = render("suggest_slot_recipe.eex", context)
    {system, user}
  end

  def plan_weekly(constraints) do
    system = """
    You are a meal planner. Think like a prep cook.
    Goal: assign recipes to meal slots for the week.
    Principles:
    - Batch cook early in the week; cascade leftovers into later meals
    - Prefer ingredient reuse over variety
    - Respect pinned slots as hard constraints
    - Prefer pantry items and deals when available
    - Weeknight slots need recipes with total time ≤45 min
    Respond with a JSON object only. No prose.
    """

    user = render("plan_weekly.eex", constraints)
    {system, user}
  end

  def prep_guide(plan) do
    system = """
    You are a sous chef. Generate a Sunday prep session guide for the week's meals.
    Think in cascades: prep components that transform into different dishes across the week.
    Respond with a JSON object only. No prose.
    """

    user = render("prep_guide.eex", plan)
    {system, user}
  end

  def estimate_nutrition do
    system = File.read!(Path.join(@prompts_dir, "estimate_nutrition.eex"))
    {system, ""}
  end

  @recipe_schema """
  {
    "title": "string (required)",
    "description": "string or null",
    "prep_time_minutes": "integer or null",
    "cook_time_minutes": "integer or null",
    "base_servings": "integer or null",
    "image_url": "absolute URL string or null",
    "tags": ["string"],
    "ingredients": [
      { "item": "string", "quantity": "number or null", "unit": "string or null" }
    ],
    "steps": [
      {
        "phase": "string — cooking phase name in ALL CAPS (e.g. MISE EN PLACE, SAUCE, ASSEMBLY, COOKING, BAKING)",
        "order": "integer — global step number starting at 1",
        "action": "string — one clear, atomic cooking action",
        "ingredients": ["string — ingredient names used in this step"],
        "duration_minutes": "integer or null — only if this step has an explicit wait/cook time"
      }
    ]
  }
  """

  @recipe_rules """
  - title is required; steps and ingredients must always be arrays (empty if unknown)
  - CRITICAL: the steps array must be sorted in the exact order a cook performs them, start to finish
  - The "order" field is a single global counter: the first thing you do is order 1, the second is order 2, etc.
  - MISE EN PLACE (prep) always comes before any cooking phase — assign it the lowest order numbers
  - Cooking phases follow in the order they are actually executed, not the order they appear in the source
  - Example of correct ordering for a meatball recipe:
      order 1 phase "MISE EN PLACE" — chop onion
      order 2 phase "MISE EN PLACE" — mix meat and breadcrumbs
      order 3 phase "COOKING" — fry meatballs
      order 4 phase "SAUCE" — make sauce in same pan
      order 5 phase "SERVING" — plate with sides
  - each step is one atomic action — never combine multiple actions in one step
  - do not summarise or skip any steps from the source
  - reference ingredient names in each step's ingredients array exactly as they appear in the top-level ingredients list
  - ingredients: list every ingredient with "item" (name), "quantity" (number or null), "unit" (string or null, e.g. "g", "ml", "dl", "st", "msk", "tsk") — use null when not specified
  - tags: 1-3 lowercase tags (cuisine, main protein, or style — e.g. "chicken", "italian", "quick", "vegetarian")
  - Respond with a JSON object only. No prose.
  """

  def extract_recipe(html) do
    system = """
    You are a recipe extractor. Given raw HTML from a recipe webpage, extract the recipe.
    Return a JSON object matching this exact structure:
    #{@recipe_schema}
    Rules:
    #{@recipe_rules}
    """

    {system, html}
  end

  def parse_recipe_images do
    system = """
    You are a recipe extractor. The user has photographed one or more pages of a recipe — ingredients may be on one image, instructions on another.
    Combine all images into a single complete recipe and return a JSON object matching this exact structure:
    #{@recipe_schema}
    Rules:
    #{@recipe_rules}
    """

    system
  end

  def parse_receipt do
    system = """
    You are a receipt parser. Extract line items from receipt images precisely.
    Respond with a JSON object only. No prose.
    """

    user = File.read!(Path.join(@prompts_dir, "parse_receipt.eex"))
    {system, user}
  end

  defp render(template, assigns) do
    path = Path.join(@prompts_dir, template)
    EEx.eval_file(path, assigns: Map.to_list(assigns))
  end
end
