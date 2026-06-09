defmodule Tore.Harness.Capsules do
  @moduledoc "Composes a run's declared capsule list into its prompt context."

  @doc """
  Build each declared capsule from ctx, render it, drop nils, join with blank
  lines. `capsule_modules` is the run's explicit, static capsule list; order is
  preserved.
  """
  @spec compose([module()], map()) :: String.t()
  def compose(capsule_modules, ctx) do
    capsule_modules
    |> Enum.map(fn mod -> mod.to_prompt(mod.build(ctx)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
end
