defmodule Scullion.Planning.Commands do
  defmodule GeneratePlan, do: defstruct [:week_start, :recipes]
  defmodule AssignRecipe, do: defstruct [:day, :recipe_id, :servings]
  defmodule RemoveRecipe, do: defstruct [:day]
  defmodule SetServings, do: defstruct [:day, :servings]
  defmodule MarkLeftover, do: defstruct [:day]

  @type t ::
          %GeneratePlan{}
          | %AssignRecipe{}
          | %RemoveRecipe{}
          | %SetServings{}
          | %MarkLeftover{}
end
