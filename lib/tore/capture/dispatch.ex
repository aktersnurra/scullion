defmodule Tore.Capture.Dispatch do
  @moduledoc """
  Handlers invoked by `Tore.Capture.Router` when the model emits a tool call.

  Each function corresponds 1:1 to a tool in the catalogue and produces a
  rendered assistant bubble (a plain map the LiveView already renders).

  These are the bodies that used to live inside `Tore.PhotoPipeline.route_group/3`,
  one per channel, lifted out so the router can call them directly.
  """

  alias Tore.Harness.Orchestrator
  alias Tore.Harness.Run
  alias Tore.Harness.Run.State
  alias Tore.Storage.RunPhotos

  @type ctx :: %{
          required(:household_id) => integer(),
          optional(:user_id) => integer() | nil
        }
  @type bubble :: map()

  # ── receipt ────────────────────────────────────────────────────────────

  @spec ingest_receipt(binary(), ctx()) :: bubble()
  def ingest_receipt(image, ctx) when is_binary(image) do
    stream_id = Run.next_stream_id()
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
  end

  # ── shelf → pantry update ──────────────────────────────────────────────

  @spec update_pantry_from_shelf(binary(), ctx()) :: bubble()
  def update_pantry_from_shelf(image, ctx) when is_binary(image) do
    stream_id = Run.next_stream_id()
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
