defmodule Tore.LLM.Tool do
  @moduledoc """
  A single tool exposed to the LLM. `parameters` is a JSON Schema map. `run`
  receives the decoded args (string-keyed) and a ctx map provided by the
  agent runtime.

      kind: :action — may mutate app state. Counted against the agent's action cap.
      kind: :read   — pure read; not counted against the action cap.
  """

  @enforce_keys [:name, :description, :parameters, :kind, :run]
  defstruct [:name, :description, :parameters, :kind, :run]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          kind: :action | :read,
          run: (map(), map() -> {:ok, term()} | {:error, term()})
        }

  @spec to_openai(t()) :: map()
  def to_openai(%__MODULE__{} = t) do
    %{
      type: "function",
      function: %{
        name: t.name,
        description: t.description,
        parameters: t.parameters
      }
    }
  end

  @spec validate_args(t(), map()) :: :ok | {:error, {:missing_arg, String.t()}}
  def validate_args(%__MODULE__{parameters: %{"required" => req}}, args), do: check_keys(req, args)
  def validate_args(%__MODULE__{parameters: %{required: req}}, args), do: check_keys(req, args)
  def validate_args(_, _), do: :ok

  defp check_keys([], _), do: :ok
  defp check_keys([k | rest], args) when is_binary(k) do
    if Map.has_key?(args, k), do: check_keys(rest, args), else: {:error, {:missing_arg, k}}
  end
  defp check_keys([k | rest], args), do: check_keys([to_string(k) | rest], args)
end
