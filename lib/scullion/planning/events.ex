defmodule Scullion.Planning.Events do
  defmodule PlanGenerated, do: defstruct [:week_start, :slots]
  defmodule RecipeAssigned, do: defstruct [:day, :recipe_id, :servings]
  defmodule RecipeRemoved, do: defstruct [:day]
  defmodule ServingsChanged, do: defstruct [:day, :servings]
  defmodule LeftoverMarked, do: defstruct [:day]

  @type t ::
          %PlanGenerated{}
          | %RecipeAssigned{}
          | %RecipeRemoved{}
          | %ServingsChanged{}
          | %LeftoverMarked{}
end
