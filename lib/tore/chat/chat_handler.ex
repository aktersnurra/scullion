defmodule Tore.Chat.ChatHandler do
  alias Tore.AiOperations
  alias Tore.Harness.Capsules

  alias Tore.Harness.Capsules.{
    HouseholdPreferencesCapsule,
    ActiveInsightsCapsule,
    WeekPlanCapsule,
    PantryBeliefsCapsule
  }

  @llm Application.compile_env(:tore, :llm_client)

  @chat_capsules [
    HouseholdPreferencesCapsule,
    ActiveInsightsCapsule,
    WeekPlanCapsule,
    PantryBeliefsCapsule
  ]

  @role_preamble "You are Tore, a friendly and practical AI cooking and meal planning assistant.\nHelp the household plan meals, manage groceries, and make the most of what they have.\nRespond conversationally in the user's language. Be concise and warm."

  @spec handle_text(String.t(), keyword()) :: {:ok, String.t(), nil} | {:error, term()}
  def handle_text(text, _opts \\ []) do
    system =
      [@role_preamble, Capsules.compose(@chat_capsules, chat_ctx())]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    messages = [%{"role" => "user", "content" => text}]
    correlation_id = generate_correlation_id()

    AiOperations.log(%{
      run_stream_id: correlation_id,
      kind: "chat",
      payload: text
    })

    case @llm.chat(system, messages) do
      {:ok, reply, _usage} ->
        AiOperations.log(%{
          run_stream_id: "#{correlation_id}:reply",
          kind: "chat_reply",
          payload: text,
          result: reply
        })

        {:ok, reply, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
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
end
