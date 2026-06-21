defmodule Tore.Capture.Dispatch do
  @moduledoc """
  Handlers invoked by `Tore.Capture.Router` when the model emits a tool call.

  Each function corresponds 1:1 to a tool in the catalogue and produces a
  rendered assistant bubble (a plain map the LiveView already renders).

  These are the bodies that used to live inside `Tore.PhotoPipeline.route_group/3`,
  one per channel, lifted out so the router can call them directly.
  """

  alias Tore.Capture.Uploads
  alias Tore.Harness.Orchestrator
  alias Tore.Harness.Run
  alias Tore.Harness.Run.State
  alias Tore.Planning
  alias Tore.Recipes
  alias Tore.Storage.RunPhotos

  @days ~w(mon tue wed thu fri sat sun)
  @day_long ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
  @default_servings 4
  @suggestion_limit 4

  @type ctx :: %{
          required(:household_id) => integer(),
          optional(:user_id) => integer() | nil
        }
  @type bubble :: map()

  # ── receipt ────────────────────────────────────────────────────────────

  @spec ingest_receipt(binary(), ctx()) :: bubble()
  def ingest_receipt(image, ctx) when is_binary(image) do
    with_dedup(image, ctx, "receipt", fn stream_id ->
      image_path = stash_photo(stream_id, image)

      dispatch_ctx = %{
        household_id: ctx.household_id,
        user_id: ctx[:user_id],
        stream_id: stream_id,
        image_binary: image,
        image_path: image_path
      }

      case Orchestrator.dispatch(:receipt_ingestion_run, dispatch_ctx) do
        {:ok, %State.NeedsUser{stream_id: sid}} ->
          inbox_bubble(:receipt, sid)

        {:ok, %State.Failed{failure_code: code}} ->
          if image_path, do: RunPhotos.delete_async(image_path)
          error_bubble(:receipt, code)

        {:error, reason} ->
          if image_path, do: RunPhotos.delete_async(image_path)
          error_bubble(:receipt, reason)
      end
    end)
  end

  # ── shelf → pantry update ──────────────────────────────────────────────

  @spec update_pantry_from_shelf(binary(), ctx()) :: bubble()
  def update_pantry_from_shelf(image, ctx) when is_binary(image) do
    with_dedup(image, ctx, "shelf", fn stream_id ->
      image_path = stash_photo(stream_id, image)

      dispatch_ctx = %{
        household_id: ctx.household_id,
        user_id: ctx[:user_id],
        stream_id: stream_id,
        channel: :shelf_photo,
        image_binary: image,
        image_path: image_path
      }

      case Orchestrator.dispatch(:pantry_belief_update_run, dispatch_ctx) do
        {:ok, %State.NeedsUser{stream_id: sid}} ->
          inbox_bubble(:pantry, sid)

        {:ok, %State.Applied{}} ->
          %{role: :assistant, text: Gettext.dgettext(ToreWeb.Gettext, "default", "Added the pantry items from your photo.")}

        {:ok, %State.Failed{failure_code: code}} ->
          error_bubble(:pantry, code)

        {:error, reason} ->
          error_bubble(:pantry, reason)
      end
    end)
  end

  # ── recipe (grouped: multi-page recipes stay together) ─────────────────

  @spec ingest_recipe([binary()], ctx()) :: bubble()
  def ingest_recipe(images, _ctx) when is_list(images) and images != [] do
    case Tore.Recipes.extract_from_images(images) do
      {:ok, %{id: id, title: title}} ->
        %{role: :assistant, recipe_card: true, recipe_id: id, title: title}

      {:ok, recipe} when is_map(recipe) ->
        %{
          role: :assistant,
          recipe_card: true,
          recipe_id: recipe[:id] || recipe["id"],
          title: recipe[:title] || recipe["title"]
        }

      {:error, reason} ->
        error_bubble(:recipe, reason)
    end
  end

  # ── fridge → suggestions ───────────────────────────────────────────────

  @spec suggest_from_fridge(binary(), ctx()) :: bubble()
  def suggest_from_fridge(image, _ctx) when is_binary(image) do
    case Tore.Pantry.parse_image(image) do
      {:ok, items} ->
        names = items |> Enum.map(&(&1[:name] || &1["name"])) |> Enum.take(5) |> Enum.join(", ")

        text =
          if names == "" do
            Gettext.dgettext(ToreWeb.Gettext, "default", "I can see your fridge but it looks empty.")
          else
            Gettext.dgettext(
              ToreWeb.Gettext,
              "default",
              "I can see %{names} in your fridge. Want me to suggest some recipes?",
              names: names
            )
          end

        %{role: :assistant, text: text}

      {:error, reason} ->
        error_bubble(:fridge, reason)
    end
  end

  # ── URL import ─────────────────────────────────────────────────────────

  @spec import_recipe_from_url(String.t(), String.t() | nil) :: bubble()
  def import_recipe_from_url(url, locale) when is_binary(url) do
    case Tore.Recipes.scrape_from_url(url, locale) do
      {:ok, recipe} ->
        %{role: :assistant, recipe_card: true, recipe_id: recipe.id, title: recipe.title}

      {:error, :not_a_recipe} ->
        %{role: :assistant, text: Gettext.dgettext(ToreWeb.Gettext, "default", "That page doesn't look like a recipe.")}

      {:error, :timeout} ->
        %{role: :assistant, text: Gettext.dgettext(ToreWeb.Gettext, "default", "The site didn't respond. Try again in a moment.")}

      {:error, _reason} ->
        %{role: :assistant, text: Gettext.dgettext(ToreWeb.Gettext, "default", "Couldn't import that URL.")}
    end
  end

  # ── recipe search ──────────────────────────────────────────────────────

  @spec find_recipe(String.t()) :: bubble()
  def find_recipe(query) when is_binary(query) do
    case Recipes.search(query) do
      [] ->
        %{
          role: :assistant,
          text:
            Gettext.dgettext(
              ToreWeb.Gettext,
              "default",
              "I couldn't find a recipe matching \"%{q}\". Want me to import one from a URL?",
              q: query
            )
        }

      [top | rest] ->
        candidates = Enum.take(rest, 2)
        titles = Enum.map_join([top | candidates], ", ", & &1.title)

        %{
          role: :assistant,
          recipe_search: true,
          top_recipe_id: top.id,
          top_title: top.title,
          candidate_ids: Enum.map(candidates, & &1.id),
          text: Gettext.dgettext(ToreWeb.Gettext, "default", "I found: %{titles}.", titles: titles)
        }
    end
  end

  # ── plan slot mutation ─────────────────────────────────────────────────

  @spec set_plan_slot(Date.t(), integer(), integer() | nil) :: bubble()
  def set_plan_slot(%Date{} = date, recipe_id, servings) when is_integer(recipe_id) do
    plan_id = plan_stream_id_for(date)
    slot_key = slot_key_for(date)
    servings = servings || @default_servings

    case Recipes.get!(recipe_id) do
      %{title: title} = _recipe ->
        case Planning.assign_recipe(plan_id, slot_key, recipe_id, servings) do
          {:ok, _events} ->
            %{
              role: :assistant,
              text:
                Gettext.dgettext(
                  ToreWeb.Gettext,
                  "default",
                  "Added %{title} to %{day} %{date}.",
                  title: title,
                  day: long_day_for(date),
                  date: Date.to_iso8601(date)
                )
            }

          {:error, reason} ->
            error_bubble(:plan, reason)
        end

      _ ->
        error_bubble(:plan, :recipe_not_found)
    end
  rescue
    Ecto.NoResultsError -> error_bubble(:plan, :recipe_not_found)
  end

  @spec clear_plan_slot(Date.t()) :: bubble()
  def clear_plan_slot(%Date{} = date) do
    plan_id = plan_stream_id_for(date)
    slot_key = slot_key_for(date)

    case Planning.remove_recipe(plan_id, slot_key) do
      {:ok, _events} ->
        %{
          role: :assistant,
          text:
            Gettext.dgettext(
              ToreWeb.Gettext,
              "default",
              "Cleared %{day} %{date}.",
              day: long_day_for(date),
              date: Date.to_iso8601(date)
            )
        }

      {:error, reason} ->
        error_bubble(:plan, reason)
    end
  end

  # ── pantry-driven suggestions ──────────────────────────────────────────

  @spec suggest_meals_from_pantry(pos_integer()) :: bubble()
  def suggest_meals_from_pantry(count) when is_integer(count) and count > 0 do
    today = Date.utc_today()
    week_start = Date.add(today, -(Date.day_of_week(today) - 1))
    plan_id = "plan:#{Date.to_iso8601(week_start)}"
    next_empty = next_empty_slot_key(today)

    case Planning.suggest_recipes_for_slot(plan_id, next_empty, limit: count) do
      {:ok, []} ->
        %{
          role: :assistant,
          text:
            Gettext.dgettext(
              ToreWeb.Gettext,
              "default",
              "Your recipe library is empty. Import a recipe and I'll suggest from your pantry next time."
            )
        }

      {:ok, ranked} ->
        suggestions =
          Enum.map(ranked, fn %{recipe: r, reasons: reasons} ->
            %{recipe_id: r.id, title: r.title, reasons: Enum.take(reasons, 2)}
          end)
          |> Enum.take(min(count, @suggestion_limit))

        %{
          role: :assistant,
          pantry_suggestions: true,
          suggestions: suggestions,
          text:
            Gettext.dgettext(
              ToreWeb.Gettext,
              "default",
              "Here's what works with what you have:"
            )
        }

      {:error, reason} ->
        error_bubble(:suggest, reason)
    end
  end

  # ── unrecognised image ─────────────────────────────────────────────────

  @spec report_unrecognised_image(String.t() | nil) :: bubble()
  def report_unrecognised_image(suggestion) do
    text =
      case suggestion do
        s when is_binary(s) and s != "" -> s
        _ -> Gettext.dgettext(ToreWeb.Gettext, "default", "I wasn't sure what that photo showed. Could you tell me — is it a receipt, a recipe, or your fridge?")
      end

    %{role: :assistant, text: text}
  end

  # ── helpers ────────────────────────────────────────────────────────────

  # Race-safe: reserve a stream_id, then try to record the hash. If the
  # unique index trips, another upload already claimed these bytes — return
  # the existing stream_id and never dispatch a duplicate run.
  defp with_dedup(image, ctx, kind, run_fn) do
    hash = Uploads.content_hash(image)
    stream_id = Run.next_stream_id()

    case Uploads.record(ctx.household_id, hash, stream_id, kind) do
      {:ok, ^stream_id} -> run_fn.(stream_id)
      {:duplicate, existing_stream_id} -> duplicate_bubble(kind, existing_stream_id)
    end
  end

  defp duplicate_bubble(_kind, _stream_id) do
    %{
      role: :assistant,
      inbox_link: true,
      text:
        Gettext.dgettext(
          ToreWeb.Gettext,
          "default",
          "You've already uploaded this photo. Find it in your inbox."
        )
    }
  end

  defp stash_photo(stream_id, image) do
    case RunPhotos.store(stream_id, image) do
      {:ok, key} ->
        key

      {:error, reason} ->
        require Logger
        Logger.warning("RunPhotos.store failed: #{inspect(reason)} (run continues)")
        nil
    end
  end

  defp inbox_bubble(:receipt, _sid) do
    %{
      role: :assistant,
      inbox_link: true,
      text: Gettext.dgettext(ToreWeb.Gettext, "default", "I parsed a receipt. Review it in your inbox.")
    }
  end

  defp inbox_bubble(:pantry, _sid) do
    %{
      role: :assistant,
      inbox_link: true,
      text: Gettext.dgettext(ToreWeb.Gettext, "default", "I parsed your shelf photo. Review it in your inbox.")
    }
  end

  defp plan_stream_id_for(%Date{} = date) do
    week_start = Date.add(date, -(Date.day_of_week(date) - 1))
    "plan:#{Date.to_iso8601(week_start)}"
  end

  defp slot_key_for(%Date{} = date) do
    day_abbrev = Enum.at(@days, Date.day_of_week(date) - 1)
    "#{day_abbrev}_dinner"
  end

  defp long_day_for(%Date{} = date), do: Enum.at(@day_long, Date.day_of_week(date) - 1)

  defp next_empty_slot_key(%Date{} = today) do
    week_start = Date.add(today, -(Date.day_of_week(today) - 1))
    plan_id = "plan:#{Date.to_iso8601(week_start)}"

    case Planning.load_plan(plan_id) do
      {:ok, state} ->
        today_idx = Date.day_of_week(today) - 1

        Enum.drop(@days, today_idx)
        |> Enum.find_value(fn day ->
          slot_key = "#{day}_dinner"

          case Map.get(state.slots, slot_key) do
            nil -> slot_key
            %{recipe_id: nil} -> slot_key
            _ -> nil
          end
        end) || "#{Enum.at(@days, today_idx)}_dinner"

      _ ->
        "#{Enum.at(@days, Date.day_of_week(today) - 1)}_dinner"
    end
  end

  defp error_bubble(kind, reason) do
    require Logger
    Logger.warning("Capture.Dispatch #{kind} failed: #{inspect(reason)}")

    %{
      role: :assistant,
      text:
        Gettext.dgettext(
          ToreWeb.Gettext,
          "default",
          "Something went wrong processing the %{kind} photo.",
          kind: to_string(kind)
        )
    }
  end
end
