defmodule Tore.Harness.Artifact do
  @spec is_rationale_complete(struct()) :: boolean()
  def is_rationale_complete(%mod{} = artifact), do: mod.is_rationale_complete(artifact)
end
