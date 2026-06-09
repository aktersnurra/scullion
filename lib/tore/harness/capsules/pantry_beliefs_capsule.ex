defmodule Tore.Harness.Capsules.PantryBeliefsCapsule do
  @behaviour Tore.Harness.Capsule

  alias Tore.Pantry

  defstruct names: [], total: 0

  @type t :: %__MODULE__{names: [String.t()], total: non_neg_integer()}

  @impl true
  def build(_ctx) do
    items = Pantry.list_inventory()
    names = items |> Enum.map(& &1.name) |> Enum.take(20)
    %__MODULE__{names: names, total: length(items)}
  end

  @impl true
  def to_prompt(%__MODULE__{names: []}), do: nil

  def to_prompt(%__MODULE__{names: names, total: total}) do
    overflow = if total > 20, do: " and #{total - 20} more", else: ""
    "Pantry has: #{Enum.join(names, ", ")}#{overflow}."
  end
end
