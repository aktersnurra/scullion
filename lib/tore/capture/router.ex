defmodule Tore.Capture.Router do
  @moduledoc """
  One LLM tool-loop per user input at /capture.

  Replaces the old two-step pipeline (image classifier → per-class dispatch)
  with a single multimodal `chat_with_tools` call. The model sees text + all
  uploaded images in one user turn and emits zero-or-more tool calls (plus
  optionally a plain reply). Each tool maps 1:1 to a handler in
  `Tore.Capture.Dispatch`.

  Self-heal: if a handler fails or the model emits no tool calls but has
  images to act on, the failed/empty result is fed back as a tool message
  and the model gets one more shot. Capped at @max_tool_loop_iterations.
  """

  alias Tore.AiOperations
  alias Tore.Capture.Dispatch
  alias Tore.Harness.Capsules

  alias Tore.Harness.Capsules.{
    HouseholdPreferencesCapsule,
    ActiveInsightsCapsule,
    WeekPlanCapsule,
    PantryBeliefsCapsule
  }

  @chat_capsules [
    HouseholdPreferencesCapsule,
    ActiveInsightsCapsule,
    WeekPlanCapsule,
    PantryBeliefsCapsule
  ]

  @role_preamble """
  You are Tore, a friendly and practical AI cooking and meal planning assistant.
  Help the household plan meals, manage groceries, and make the most of what they have.
  Respond conversationally in the user's language. Be concise and warm.

  When the user uploads images or pastes URLs, call the appropriate tool(s).
  Group multi-page recipes into a single `ingest_recipe` call by listing all
  page indices in `image_indices`. Receipts, shelves, and fridges are
  per-image — emit one tool call per image. If an image isn't recognisable,
  call `report_unrecognised_image` with a helpful suggestion.

  When the user asks to plan a meal:
    - To slot a known recipe on a day, call `set_plan_slot` with an ISO date
      (use today's date plus the day-of-week math; do not guess).
    - If the user names a recipe by phrase (e.g. "pizza"), first call
      `find_recipe` with the query, then `set_plan_slot` using the returned
      recipe id once it's confirmed.
    - To clear a day, call `clear_plan_slot` with an ISO date.
    - When the user asks what to cook, call `suggest_meals_from_pantry`.

  Never claim a plan change happened without calling the tool. The tool result
  is ground truth.

  When there is nothing actionable, reply with plain text.
  """

  @max_tool_loop_iterations 2

  @type ctx :: %{
          required(:household_id) => integer(),
          optional(:user_id) => integer() | nil,
          optional(:locale) => String.t() | nil
        }
  @type reply :: map()

  @spec route(String.t(), [binary()], ctx()) :: {:ok, [reply()]} | {:error, term()}
  def route(text, images, ctx) when is_binary(text) and is_list(images) and is_map(ctx) do
    correlation_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    AiOperations.log(%{
      run_stream_id: correlation_id,
      kind: "capture_route",
      payload: %{"text" => text, "image_count" => length(images)}
    })

    system =
      [@role_preamble, date_line(), Capsules.compose(@chat_capsules, chat_ctx())]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    user_message = build_multimodal_user(text, images)

    loop(system, [user_message], images, ctx, correlation_id, 0)
  end

  # ── tool-loop ──────────────────────────────────────────────────────────

  defp loop(_system, _messages, _images, _ctx, _cid, iter)
       when iter > @max_tool_loop_iterations do
    {:ok, [%{role: :assistant, text: fallback_text()}]}
  end

  defp loop(system, messages, images, ctx, correlation_id, iter) do
    case Tore.LLM.chat_with_tools(system, messages, tool_catalogue(), tool_choice: tool_choice(images)) do
      {:ok, {:message, text}, _usage} ->
        {:ok, [%{role: :assistant, text: text}]}

      {:ok, {:tool_calls, calls}, _usage} ->
        {bubbles, failures} = dispatch_calls(calls, images, ctx)

        cond do
          failures == [] ->
            {:ok, bubbles}

          iter == @max_tool_loop_iterations ->
            {:ok, bubbles}

          true ->
            assistant_msg = %{role: "assistant", content: nil, tool_calls: raw_tool_calls(calls)}
            tool_msgs = Enum.map(failures, &tool_error_message/1)
            loop(system, messages ++ [assistant_msg] ++ tool_msgs, images, ctx, correlation_id, iter + 1)
        end

      {:error, reason} ->
        require Logger
        Logger.warning("Capture.Router LLM call failed: #{inspect(reason)}")
        {:ok, [%{role: :assistant, text: fallback_text()}]}
    end
  end

  # ── tool dispatch ──────────────────────────────────────────────────────

  defp dispatch_calls(calls, images, ctx) do
    image_count = length(images)

    Enum.reduce(calls, {[], []}, fn call, {bubbles, failures} ->
      case run_call(call, images, image_count, ctx) do
        {:ok, more_bubbles} ->
          {bubbles ++ more_bubbles, failures}

        {:error, reason} ->
          failure = %{tool_call: call, reason: reason}
          {bubbles, failures ++ [failure]}
      end
    end)
  end

  defp run_call(%{name: "ingest_receipt", args: args}, images, image_count, ctx) do
    with {:ok, indices} <- fetch_indices(args, image_count) do
      bubbles = Enum.map(indices, fn i -> Dispatch.ingest_receipt(Enum.at(images, i - 1), ctx) end)
      {:ok, bubbles}
    end
  end

  defp run_call(%{name: "ingest_recipe", args: args}, images, image_count, ctx) do
    with {:ok, indices} <- fetch_indices(args, image_count) do
      grouped = Enum.map(indices, &Enum.at(images, &1 - 1))
      {:ok, [Dispatch.ingest_recipe(grouped, ctx)]}
    end
  end

  defp run_call(%{name: "update_pantry_from_shelf", args: args}, images, image_count, ctx) do
    with {:ok, indices} <- fetch_indices(args, image_count) do
      bubbles =
        Enum.map(indices, fn i ->
          Dispatch.update_pantry_from_shelf(Enum.at(images, i - 1), ctx)
        end)

      {:ok, bubbles}
    end
  end

  defp run_call(%{name: "suggest_from_fridge", args: args}, images, image_count, ctx) do
    with {:ok, indices} <- fetch_indices(args, image_count) do
      bubbles = Enum.map(indices, fn i -> Dispatch.suggest_from_fridge(Enum.at(images, i - 1), ctx) end)
      {:ok, bubbles}
    end
  end

  defp run_call(%{name: "import_recipe_from_url", args: %{"url" => url}}, _images, _count, ctx)
       when is_binary(url) do
    {:ok, [Dispatch.import_recipe_from_url(url, ctx[:locale])]}
  end

  defp run_call(%{name: "report_unrecognised_image", args: args}, _images, _count, _ctx) do
    {:ok, [Dispatch.report_unrecognised_image(args["suggestion"])]}
  end

  defp run_call(%{name: "find_recipe", args: %{"query" => q}}, _images, _count, _ctx)
       when is_binary(q) do
    {:ok, [Dispatch.find_recipe(q)]}
  end

  defp run_call(%{name: "set_plan_slot", args: args}, _images, _count, _ctx) do
    with {:ok, date} <- parse_iso_date(args["date"]),
         {:ok, recipe_id} <- fetch_recipe_id(args) do
      {:ok, [Dispatch.set_plan_slot(date, recipe_id, args["servings"])]}
    end
  end

  defp run_call(%{name: "clear_plan_slot", args: %{"date" => date_str}}, _images, _count, _ctx) do
    with {:ok, date} <- parse_iso_date(date_str) do
      {:ok, [Dispatch.clear_plan_slot(date)]}
    end
  end

  defp run_call(%{name: "suggest_meals_from_pantry", args: args}, _images, _count, _ctx) do
    count = args["count"] || 4
    {:ok, [Dispatch.suggest_meals_from_pantry(count)]}
  end

  defp run_call(%{name: name}, _images, _count, _ctx) do
    {:error, {:unknown_tool, name}}
  end

  defp parse_iso_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, {:invalid_date, str}}
    end
  end

  defp parse_iso_date(_), do: {:error, :missing_date}

  defp fetch_recipe_id(%{"recipe_id" => id}) when is_integer(id), do: {:ok, id}
  defp fetch_recipe_id(_), do: {:error, :missing_recipe_id}

  defp fetch_indices(%{"image_indices" => indices}, image_count)
       when is_list(indices) and indices != [] do
    validated =
      Enum.reduce_while(indices, [], fn
        i, acc when is_integer(i) and i >= 1 and i <= image_count -> {:cont, [i | acc]}
        i, _acc -> {:halt, {:invalid_index, i}}
      end)

    case validated do
      {:invalid_index, i} -> {:error, {:image_index_out_of_range, i, image_count}}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp fetch_indices(_, _), do: {:error, :missing_image_indices}

  # ── tool catalogue (OpenAI function schema) ────────────────────────────

  defp tool_catalogue do
    [
      tool("ingest_receipt",
        "Parse a store receipt and surface an editable card in the inbox.",
        image_indices_schema()
      ),
      tool("ingest_recipe",
        "Extract a recipe from one or more photos (group multi-page recipes by listing all page indices).",
        image_indices_schema()
      ),
      tool("update_pantry_from_shelf",
        "Read pantry items from a shelf or counter photo and update the household's pantry beliefs.",
        image_indices_schema()
      ),
      tool("suggest_from_fridge",
        "Read fridge contents from a photo and suggest recipes from what's visible.",
        image_indices_schema()
      ),
      tool("import_recipe_from_url",
        "Scrape a recipe from a URL the user pasted.",
        %{
          type: "object",
          properties: %{url: %{type: "string", description: "The full http(s) URL to scrape."}},
          required: ["url"],
          additionalProperties: false
        }
      ),
      tool("report_unrecognised_image",
        "Use when an image can't be recognised — provide a short suggestion of what the user could try.",
        %{
          type: "object",
          properties: %{
            suggestion: %{
              type: "string",
              description: "Short user-facing suggestion (one sentence)."
            }
          },
          required: ["suggestion"],
          additionalProperties: false
        }
      ),
      tool("find_recipe",
        "Search the recipe library by title or ingredient. Use this before set_plan_slot when the user names a recipe by phrase rather than id.",
        %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Free-text title or ingredient query."}
          },
          required: ["query"],
          additionalProperties: false
        }
      ),
      tool("set_plan_slot",
        "Assign a known recipe to a specific date's dinner slot. Date must be ISO yyyy-mm-dd (compute it yourself from today's date and the day-of-week the user mentioned).",
        %{
          type: "object",
          properties: %{
            date: %{type: "string", description: "ISO 8601 date (yyyy-mm-dd)."},
            recipe_id: %{type: "integer", description: "The recipe's numeric id from find_recipe."},
            servings: %{type: "integer", description: "Optional servings; defaults to 4 if omitted."}
          },
          required: ["date", "recipe_id"],
          additionalProperties: false
        }
      ),
      tool("clear_plan_slot",
        "Remove any recipe assigned to a specific date's dinner slot.",
        %{
          type: "object",
          properties: %{
            date: %{type: "string", description: "ISO 8601 date (yyyy-mm-dd)."}
          },
          required: ["date"],
          additionalProperties: false
        }
      ),
      tool("suggest_meals_from_pantry",
        "Return up to `count` recipe suggestions ranked by what's in the pantry, on sale, and not recently cooked. Use when the user asks what to cook with no specific recipe in mind.",
        %{
          type: "object",
          properties: %{
            count: %{type: "integer", description: "How many suggestions (1-4)."}
          },
          required: ["count"],
          additionalProperties: false
        }
      )
    ]
  end

  defp tool(name, description, parameters) do
    %{
      type: "function",
      function: %{name: name, description: description, parameters: parameters}
    }
  end

  defp image_indices_schema do
    %{
      type: "object",
      properties: %{
        image_indices: %{
          type: "array",
          items: %{type: "integer", minimum: 1},
          description: "1-based indices into the user's uploaded images."
        }
      },
      required: ["image_indices"],
      additionalProperties: false
    }
  end

  defp tool_choice([]), do: "auto"
  defp tool_choice(_images), do: "required"

  # ── message construction ───────────────────────────────────────────────

  defp build_multimodal_user(text, []) do
    %{role: "user", content: text}
  end

  defp build_multimodal_user(text, images) do
    parts =
      [%{type: "text", text: text_with_image_index(text, length(images))}] ++
        Enum.map(images, fn bin ->
          %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{Base.encode64(bin)}"}}
        end)

    %{role: "user", content: parts}
  end

  defp text_with_image_index(text, count) do
    annotation =
      case count do
        1 -> "[Attached: 1 image, referred to as image 1.]"
        n -> "[Attached: #{n} images, referred to as images 1..#{n} in order.]"
      end

    if String.trim(text) == "", do: annotation, else: "#{text}\n\n#{annotation}"
  end

  defp raw_tool_calls(calls) do
    Enum.map(calls, fn %{id: id, name: name, args: args} ->
      %{
        id: id,
        type: "function",
        function: %{name: name, arguments: Jason.encode!(args)}
      }
    end)
  end

  defp tool_error_message(%{tool_call: %{id: id, name: name}, reason: reason}) do
    %{
      role: "tool",
      tool_call_id: id,
      name: name,
      content: "error: #{inspect(reason)}. Try a different tool or reply in plain text."
    }
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp date_line do
    "Today is #{Calendar.strftime(Date.utc_today(), "%A, %B %-d, %Y")}."
  end

  defp chat_ctx do
    today = Date.utc_today()
    week_start = Date.add(today, -(Date.day_of_week(today) - 1))

    %{
      household_id: nil,
      plan_stream_id: "plan:#{Date.to_iso8601(week_start)}",
      week_start: week_start
    }
  end

  defp fallback_text do
    Gettext.dgettext(ToreWeb.Gettext, "default", "Sorry, I couldn't process that. Please try again.")
  end
end
