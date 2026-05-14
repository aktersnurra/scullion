# Image generation pipeline

> **DONE** (`3d6a982c`)

Recipe
  → LLM visual prompt generator
  → Image prompt
  → Image model
  → Cached generated image

# Receipt from image

Parse the image of the recipe and extract each line item as a pantry item

1. image -> image to text model -> total cost + pantry entries (should be able to edit)

# Image to Pantry

> **DONE** — photo upload → vision LLM → editable preview → confirm adds to pantry

Take an image -> image to text model -> pantry entries (editable)

# Stored recipe format

> **DONE** (`11689d6d`) — recipe instructions rendered as markdown via MDEx

Free text (instructions) should be stored with markdown syntax

# Stored recipes in the locale/language of the user

> **DONE** (`edeab03a`) — parsed recipes are translated into user locale at extraction time

When parsing recipes from external sources, url/images, update the prompt to 
instruct the llm to translate the recipe into the users locale/language

# use open router structured outputs

> **DONE** (`64e9bb0e`) — json_schema structured outputs used for recipe and receipt parsing

Use structured outputs for recipe parsing, pantry item parsing, cost parsing, etc (if not already implemented)

See context below.

Yes, OpenRouter supports structured outputs via `response_format`. Let me build you a recipe converter artifact that takes unstructured text and returns structured JSON matching your schema.Now let me build the artifact. The key insight here: I'll use OpenRouter's `response_format` with `json_schema` mode, and let you define your own schema in the UI so it's reusable across any recipe format you need.Here's what's wired up:

**How the OpenRouter call works:**
```js
response_format: {
  type: "json_schema",
  json_schema: schema  // your editable schema object, passed verbatim
}
```
The model is constrained to return JSON matching the schema exactly — no parsing heuristics needed, you just `JSON.parse(content)` and it's done.

**Key design decisions:**
- The schema is **editable live in the left panel** — paste your own schema and it's used immediately. This is the main thing to customise for your meal planning format.
- `strict: true` with `additionalProperties: false` on every object — OpenRouter enforces this at the token level on supported models.
- Works with any model ID you type in — `openai/gpt-4o-mini` is a good default for structured extraction (cheap, fast, reliable schema adherence). `anthropic/claude-sonnet-4-5` also works via OpenRouter.

**Things to swap for your app:**
1. Replace the schema in the left panel with your actual meal planning schema
2. The `HTTP-Referer` and `X-Title` headers — set these to your app's domain/name (OpenRouter uses them for rate limiting attribution)
3. You'll want to move the API key to a backend call rather than the client in production

# Normalized pantry items etc

> **DONE** (`4ed4e166`) — canonical ingredient keys added with auto-derivation from name

## Use canonical keys for entities, not for full content

Good:

* ingredients
* units
* tags
* cuisines
* meal types

Bad:

* recipe titles
* instructions
* notes
* descriptions

---

## Why

Canonical keys solve:

* deduplication
* matching
* filtering
* aggregation
* AI consistency

Example:

```json id="fjlwm5"
{
  "ingredient_key": "gul_lok",
  "display_name": "gul lök"
}
```

Now:

* "gul lök"
* "gul lökar"
* "yellow onion"

can all map to:

```text id="q5jlwv"
gul_lok
```

---

## Use canonical keys when:

* data is reused
* data needs matching/searching
* values should be consistent
* values drive logic

Examples:

* pantry matching
* shopping lists
* dietary tags
* cuisine filters

---

## Don't canonicalize user-facing prose

Store directly:

* recipe text
* titles
* instructions

in Swedish.

---

## Suggested convention

### Ingredient

```text id="77k93g"
gul_lok
```

### Tags

```text id="ycvjlwm"
hog_protein
snabb_middag
vegetarisk
```

### Units

```text id="9bz10o"
g
kg
ml
dl
tsk
msk
```

---

## Recommended structure

```json id="pocjlwm"
{
  "ingredient_key": "gul_lok",
  "display_name": "gul lök",
  "amount": 1,
  "unit": "st"
}
```

---

## Practical rule

Canonicalize:

> reusable structured data

Do NOT canonicalize:

> human-readable content.

# Parsing recipe url

> **DONE** (`22b4d2437f`) — cheap pre-flight check added before expensive LLM extraction

Add a prestep with a cheap model to verify that the parsed content actually contain the recipe, otherwise
just return information about the page using js to display the recipe, hence screenshots are needed
instead.

I want to avoid spending api credits on an expensive model if the parse html does not 
contain the recipe, i.e.:

url -> html content -> cheap llm recipe parsable? y/n -> if y -> extract recipe with expensive llm

Investigation:
1. how is it implemented now? html sent to llm regardless?
2. should this step be introduced for all parsers?


# Rename project

> **DONE** — renamed from scullion to tore (homage to Tore Wretman)

Rename the project from scullion to tore (homage to Tore Wretman)

# Update README

> **DONE** — full README with architecture, tech stack, patterns, and getting started

Update readme after name change, include all the interesting stuff about the project, tree overview etc

# Add system prompt config in settings

> **DONE** (`94b078b2`, `be44275e`) — dietary guidance saved in user preferences and injected into plan/suggestion prompts; Swedish translations included

I want to be able to add custom dietary guidance to the recipe generation prompt. E.g. `generate recipes that uses less carbs, high protein`
this should be injected into the system prompt of that flow
Add this in the settings page?

# Add stuff to the pantry via photo

> **DONE** — same as Image to Pantry above; camera button on pantry page

Upload a photo on the pantry page -> vision llm -> pantry items (editable)

# Run scraping of custom url for deals

Add feature to input custom url for parsing of deals to run once

# Add urls for recurring scraping of deals
add urls for recurring scraping of deals. Maybe unify with run scraping once
