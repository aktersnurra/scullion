defmodule Tore.Harness.AmbientScan do
  @moduledoc """
  Pure helpers for `:ambient_scan_run` — the headless Tier-0 run that
  predicts at most one actionable interaction per surface, materialized as
  `counter_notes` rows with a `proposed_run`. Modeled 1:1 on
  `Tore.Harness.KitchenMemorySynthesis`.
  """

  alias Tore.CounterNotes
  alias Tore.Harness.Capsules

  alias Tore.Harness.Capsules.{
    WeekPlanCapsule,
    PantryBeliefsCapsule,
    ActiveInsightsCapsule,
    RecentHistoryCapsule
  }

  alias Tore.Harness.Orchestrator

  @capsules [
    WeekPlanCapsule,
    PantryBeliefsCapsule,
    ActiveInsightsCapsule,
    RecentHistoryCapsule
  ]

  @days ~w(mon tue wed thu fri sat sun)
  @static_slot_keys MapSet.new(Enum.map(@days, &"#{&1}_dinner"))

  @system_prompt """
  You are the ambient scanner for a single-household meal planner. From the
  week plan, pantry beliefs, insights, recent history, and the current
  shopping list, predict at most 3 interactions the household is about to
  need — one per surface at most.

  Return ONLY JSON:
  {"notes": [{"surface": "home|week|groceries",
              "kind": "swap_suggestion|freezer_fallback|missing_ingredient|usual_item_missing",
              "title": "...", "body": "...",
              "confidence": "low|medium|high",
              "scoped_slot": "tue_dinner" | null,
              "command": "imperative planner command" | null,
              "item": {"name": "...", "quantity": null, "unit": null} | null}]}

  Rules: kinds — swap_suggestion (a hard slot on a busy day; scoped_slot and
  command required), freezer_fallback (a frozen leftover fits a busy slot;
  scoped_slot and command required), missing_ingredient (tonight's recipe
  needs something pantry beliefs say is absent; command optional),
  usual_item_missing (a habitual purchase absent from the list; item
  required, no command). Title ≤ 8 words, body ≤ 2 short sentences,
  matter-of-fact, no greetings. Predict nothing rather than something
  generic. Never re-propose a dismissed note. Empty list is a fine answer.
  """

  @doc """
  Cron entry: gate on SpendGuard, build ctx exactly like
  `KitchenMemorySynthesis.synthesise_weekly/0`, and dispatch the scan run.
  """
  @spec scan(keyword()) :: {:ok, term()} | {:error, term()}
  def scan(_opts \\ []) do
    with :ok <- Tore.SpendGuard.allow?(:ambient_scan) do
      household = Tore.Household.get_household!()

      ctx = %{
        household_id: household.id,
        user_id: nil,
        plan_stream_id: "plan:#{Date.to_iso8601(Date.utc_today())}",
        week_start: Date.utc_today()
      }

      Orchestrator.dispatch(:ambient_scan_run, ctx)
    end
  end

  @spec capsules() :: [module()]
  def capsules, do: @capsules

  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @doc """
  Compose the declared capsules for `ctx`, then append the current shopping
  list and the recently-dismissed section.
  """
  @spec build_context(map()) :: String.t()
  def build_context(ctx) do
    capsule_context = Capsules.compose(@capsules, ctx)

    [capsule_context, shopping_list_section(ctx), recently_dismissed_section()]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp shopping_list_section(ctx) do
    list_id = shop_list_id(Map.get(ctx, :week_start) || Date.utc_today())

    case Tore.Shop.load_list(list_id) do
      {:ok, %{items: items}} when map_size(items) > 0 ->
        lines =
          items
          |> Map.values()
          |> Enum.map(fn item ->
            qty = format_qty(item.quantity, item.unit)
            "- #{item.name}#{qty} [#{item.section}]"
          end)

        Enum.join(["Current shopping list:" | lines], "\n")

      _ ->
        nil
    end
  end

  defp format_qty(nil, nil), do: ""
  defp format_qty(nil, unit), do: " (#{unit})"
  defp format_qty(quantity, nil), do: " (#{quantity})"
  defp format_qty(quantity, unit), do: " (#{quantity} #{unit})"

  defp shop_list_id(week_start), do: "shop_list:#{Date.to_iso8601(week_start)}"

  defp recently_dismissed_section do
    heading = "Recently dismissed by the household — do NOT re-propose these:"

    lines =
      case CounterNotes.recently_ignored(14) do
        [] ->
          ["(none)"]

        dismissed ->
          Enum.map(dismissed, fn %{kind: kind, title: title} -> "- #{kind}: #{title}" end)
      end

    Enum.join([heading | lines], "\n")
  end

  @doc """
  The week plan's slot-key domain, falling back to the static 7-key set
  when the plan is empty.
  """
  @spec slot_keys(map()) :: MapSet.t()
  def slot_keys(%{slots: slots}) when map_size(slots) > 0, do: MapSet.new(Map.keys(slots))
  def slot_keys(_plan), do: @static_slot_keys

  @doc """
  Verify each raw proposal against the slot-key domain, drop failures, and
  cap at one note per surface (first wins).
  """
  @spec verify_and_cap([map()], MapSet.t()) :: [map()]
  def verify_and_cap(notes, slot_keys) when is_list(notes) do
    notes
    |> Enum.map(&drop_nil_optionals/1)
    |> Enum.filter(&(Tore.Harness.Verifier.CounterNoteVerifier.verify(&1, slot_keys) == :ok))
    |> Enum.uniq_by(& &1["surface"])
  end

  def verify_and_cap(_notes, _slot_keys), do: []

  # The LLM's JSON always includes scoped_slot/command/item keys with a nil
  # value when unused; the verifier treats a present-but-nil "item" key as
  # "unexpectedly carrying an item". Drop nil-valued optional keys before
  # verification so a literal `"item": null` reads the same as an absent key.
  defp drop_nil_optionals(note) do
    Enum.reduce(~w(scoped_slot command item), note, fn key, acc ->
      if Map.get(acc, key) == nil, do: Map.delete(acc, key), else: acc
    end)
  end

  @doc "Map a verified proposal to `CounterNotes.replace_scan_notes/1` attrs."
  @spec to_attrs(map()) :: map()
  def to_attrs(note) do
    %{
      surface: note["surface"],
      kind: note["kind"],
      title: note["title"],
      body: note["body"],
      confidence: note["confidence"],
      proposed_run: proposed_run(note),
      expires_at: next_five_am()
    }
  end

  defp proposed_run(%{"command" => command} = note) when is_binary(command) do
    %{"kind" => "planner_command", "command" => command, "scoped_slot" => note["scoped_slot"]}
  end

  defp proposed_run(%{"item" => %{"name" => name} = item}) when is_binary(name) do
    %{
      "kind" => "add_item",
      "name" => name,
      "quantity" => item["quantity"],
      "unit" => item["unit"]
    }
  end

  defp proposed_run(_note), do: nil

  defp next_five_am do
    DateTime.utc_now()
    |> DateTime.add(1, :day)
    |> then(&%{&1 | hour: 5, minute: 0, second: 0, microsecond: {0, 0}})
  end
end
