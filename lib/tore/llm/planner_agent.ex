defmodule Tore.LLM.PlannerAgent do
  @moduledoc """
  Bounded tool-calling loop for the planner command bar. See SPEC.md §2.

  Returns one of:

      {:ok, %{
        final_message: String.t() | nil,
        question:      String.t() | nil,
        actions:       [%{name: String.t(), ok: boolean(), error: term() | nil}],
        capped:        boolean(),
        correlation_id: String.t()
      }}
      {:error, term()}
  """

  alias Tore.LLM.{Tool, PlannerTools}

  @llm Application.compile_env(:tore, :llm_client)

  @default_max_round_trips 6
  @default_max_action_calls 12

  @spec run(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(user_text, ctx, opts \\ []) do
    max_round_trips = Keyword.get(opts, :max_round_trips, @default_max_round_trips)
    max_action_calls = Keyword.get(opts, :max_action_calls, @default_max_action_calls)
    correlation_id = Keyword.get(opts, :correlation_id, generate_cid())

    tools = PlannerTools.all()
    tools_json = Enum.map(tools, &Tool.to_openai/1)
    system_prompt = Tore.Chat.SystemPrompt.build()

    state = %{
      ctx: Map.put(ctx, :correlation_id, correlation_id),
      tools_by_name: Map.new(tools, &{&1.name, &1}),
      tools_json: tools_json,
      messages: [%{role: "user", content: user_text}],
      actions: [],
      step_index: 0,
      action_calls: 0,
      round_trips: 0,
      max_round_trips: max_round_trips,
      max_action_calls: max_action_calls,
      correlation_id: correlation_id,
      capped: false,
      question: nil
    }

    loop(system_prompt, state)
  end

  # ---------- Loop ----------

  defp loop(system, %{round_trips: rt, max_round_trips: max} = state) when rt >= max do
    case @llm.chat_with_tools(system, state.messages, [], []) do
      {:ok, {:message, text}, usage} ->
        log(state, usage, "capped_final", text)
        finish(%{state | capped: true}, text)

      {:ok, _other, usage} ->
        log(state, usage, "capped_unknown", "")
        finish(%{state | capped: true}, "Stopped — too many steps.")

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp loop(system, state) do
    case @llm.chat_with_tools(system, state.messages, state.tools_json, []) do
      {:ok, {:message, text}, usage} ->
        log(state, usage, "message", text)
        finish(state, text)

      {:ok, {:tool_calls, calls}, usage} ->
        log(state, usage, "tool_calls", encode_calls(calls))
        state = %{state | step_index: state.step_index + 1, round_trips: state.round_trips + 1}

        # Append a single assistant turn containing all tool_calls before any results.
        state = append_assistant_tool_calls(state, calls)

        case execute_calls(calls, state) do
          {:terminal_question, question, state} ->
            {:ok,
             %{
               final_message: nil,
               question: question,
               actions: Enum.reverse(state.actions),
               capped: false,
               correlation_id: state.correlation_id
             }}

          {:cap_hit, state} ->
            loop(system, %{state | round_trips: state.max_round_trips})

          {:continue, state} ->
            loop(system, state)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_calls([], state), do: {:continue, state}

  defp execute_calls([call | rest], state) do
    case Map.fetch(state.tools_by_name, call.name) do
      :error ->
        state = append_tool_result(state, call, %{error: "unknown_tool"})
        execute_calls(rest, state)

      {:ok, tool} ->
        handle_tool(tool, call, rest, state)
    end
  end

  defp handle_tool(%Tool{name: "ask_user"} = tool, call, _rest, state) do
    case Tool.validate_args(tool, call.args) do
      :ok ->
        {:ok, %{ask_user: question}} = tool.run.(call.args, state.ctx)
        state = append_tool_result(state, call, %{ok: true, question: question})
        {:terminal_question, question, state}

      {:error, _} = err ->
        state = append_tool_result(state, call, %{error: inspect(err)})
        {:continue, state}
    end
  end

  defp handle_tool(%Tool{kind: :action} = tool, call, rest, state) do
    if state.action_calls >= state.max_action_calls do
      state = append_tool_result(state, call, %{error: "action_cap_reached"})
      {:cap_hit, %{state | actions: [%{name: call.name, ok: false, error: :cap} | state.actions]}}
    else
      run_and_record(tool, call, rest, %{state | action_calls: state.action_calls + 1})
    end
  end

  defp handle_tool(%Tool{kind: :read} = tool, call, rest, state) do
    run_and_record(tool, call, rest, state)
  end

  defp run_and_record(tool, call, rest, state) do
    case Tool.validate_args(tool, call.args) do
      :ok ->
        case tool.run.(call.args, state.ctx) do
          {:ok, result} ->
            state = append_tool_result(state, call, result)

            state =
              if tool.kind == :action,
                do: %{state | actions: [%{name: call.name, ok: true, error: nil} | state.actions]},
                else: state

            execute_calls(rest, state)

          {:error, reason} ->
            state = append_tool_result(state, call, %{error: inspect(reason)})

            state =
              if tool.kind == :action,
                do: %{state | actions: [%{name: call.name, ok: false, error: reason} | state.actions]},
                else: state

            execute_calls(rest, state)
        end

      {:error, reason} ->
        state = append_tool_result(state, call, %{error: inspect(reason)})
        execute_calls(rest, state)
    end
  end

  defp append_tool_result(state, call, result) do
    msg = %{
      role: "tool",
      tool_call_id: call.id,
      name: call.name,
      content: Jason.encode!(result)
    }

    %{state | messages: state.messages ++ [msg]}
  end

  defp append_assistant_tool_calls(state, calls) do
    msg = %{
      role: "assistant",
      content: nil,
      tool_calls:
        Enum.map(calls, fn call ->
          %{
            id: call.id,
            type: "function",
            function: %{name: call.name, arguments: Jason.encode!(call.args)}
          }
        end)
    }

    %{state | messages: state.messages ++ [msg]}
  end

  defp finish(state, final_message) do
    {:ok,
     %{
       final_message: final_message,
       question: nil,
       actions: Enum.reverse(state.actions),
       capped: state.capped,
       correlation_id: state.correlation_id
     }}
  end

  defp log(state, usage, kind, result) do
    Tore.AiOperations.log(%{
      correlation_id: state.correlation_id,
      kind: "planner_agent." <> kind,
      step_index: state.step_index,
      payload: Jason.encode!(%{messages_count: length(state.messages), usage: usage}),
      result: truncate(result, 4_000)
    })

    :ok
  end

  defp encode_calls(calls), do: Jason.encode!(calls)

  defp truncate(s, max) when is_binary(s) do
    if String.length(s) > max do
      String.slice(s, 0, max) <> "…"
    else
      s
    end
  end

  defp truncate(s, _), do: s

  defp generate_cid do
    "pa-" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end
end
