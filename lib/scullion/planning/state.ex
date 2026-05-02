defmodule Scullion.Planning.State do
  defstruct week_start: nil,
            slot_config: %{},
            slots: %{},
            pins: %{}

  @type t :: %__MODULE__{
          week_start: Date.t() | nil,
          slot_config: map(),
          slots: map(),
          pins: map()
        }
end
