defmodule Tore.Planning.Events do
  defmodule PlanGenerated, do: defstruct([:week_start, :slots])
  defmodule RecipeAssigned, do: defstruct([:slot_key, :recipe_id, :servings])
  defmodule RecipeRemoved, do: defstruct([:slot_key])
  defmodule ServingsChanged, do: defstruct([:slot_key, :servings])
  defmodule SlotPinned, do: defstruct([:slot_key, :pin])
  defmodule SlotUnpinned, do: defstruct([:slot_key])
  defmodule MealSkipped, do: defstruct([:slot_key])
  defmodule LeftoverMarked, do: defstruct([:slot_key])

  @type t ::
          %PlanGenerated{}
          | %RecipeAssigned{}
          | %RecipeRemoved{}
          | %ServingsChanged{}
          | %SlotPinned{}
          | %SlotUnpinned{}
          | %MealSkipped{}
          | %LeftoverMarked{}
end
