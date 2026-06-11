defmodule Tore.Shop.State do
  defstruct week_start: nil, items: %{}

  @type t :: %__MODULE__{
          week_start: Date.t() | nil,
          items: %{String.t() => map()}
        }
end
