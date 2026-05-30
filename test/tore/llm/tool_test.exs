defmodule Tore.LLM.ToolTest do
  use ExUnit.Case, async: true
  alias Tore.LLM.Tool

  test "describes itself as a JSON-serialisable map" do
    t = %Tool{
      name: "skip_meal",
      description: "Mark a slot skipped",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{slot_key: %{type: "string"}},
        required: ["slot_key"]
      },
      run: fn _args, _ctx -> {:ok, %{ok: true}} end
    }

    assert Tool.to_openai(t) == %{
             type: "function",
             function: %{
               name: "skip_meal",
               description: "Mark a slot skipped",
               parameters: %{
                 type: "object",
                 properties: %{slot_key: %{type: "string"}},
                 required: ["slot_key"]
               }
             }
           }
  end

  test "validates required arguments" do
    t = %Tool{
      name: "skip_meal",
      description: "x",
      kind: :action,
      parameters: %{
        type: "object",
        properties: %{slot_key: %{type: "string"}},
        required: ["slot_key"]
      },
      run: fn _, _ -> {:ok, %{}} end
    }

    assert {:error, {:missing_arg, "slot_key"}} = Tool.validate_args(t, %{})
    assert :ok = Tool.validate_args(t, %{"slot_key" => "mon_dinner"})
  end
end
