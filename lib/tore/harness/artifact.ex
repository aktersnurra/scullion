defmodule Tore.Harness.Artifact do
  @type kind :: String.t()
  @type t :: struct()

  @callback kind() :: kind()
  @callback to_json(t()) :: map()
  @callback from_json(map()) :: t()
  @callback summary(t()) :: %{
              counts: %{atom() => non_neg_integer()},
              text_fallback: String.t()
            }
  @callback is_rationale_complete(t()) :: boolean()

  @spec is_rationale_complete(t()) :: boolean()
  def is_rationale_complete(%mod{} = artifact), do: mod.is_rationale_complete(artifact)

  @spec summary(t()) :: map()
  def summary(%mod{} = artifact), do: mod.summary(artifact)

  @spec to_json(t()) :: map()
  def to_json(%mod{} = artifact), do: Map.put(mod.to_json(artifact), "__kind__", mod.kind())
end
