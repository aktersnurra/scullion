defmodule Scullion.Planning.State do
  defstruct week_start: nil, slots: %{}

  @type t :: %__MODULE__{
          week_start: Date.t() | nil,
          slots: %{atom() => map()}
        }
end
