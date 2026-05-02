defmodule Scullion.Planning.Commands do
  defmodule GeneratePlan, do: defstruct([:week_start, :slots])
  defmodule AssignRecipe, do: defstruct([:slot_key, :recipe_id, :servings])
  defmodule RemoveRecipe, do: defstruct([:slot_key])
  defmodule SetServings, do: defstruct([:slot_key, :servings])
  defmodule PinSlot, do: defstruct([:slot_key, :pin])
  defmodule UnpinSlot, do: defstruct([:slot_key])
  defmodule SkipMeal, do: defstruct([:slot_key])
  defmodule MarkLeftover, do: defstruct([:slot_key])

  @type t ::
          %GeneratePlan{}
          | %AssignRecipe{}
          | %RemoveRecipe{}
          | %SetServings{}
          | %PinSlot{}
          | %UnpinSlot{}
          | %SkipMeal{}
          | %MarkLeftover{}
end
