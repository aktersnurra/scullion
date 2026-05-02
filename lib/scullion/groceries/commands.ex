defmodule Scullion.Groceries.Commands do
  defmodule BuildList, do: defstruct([:week_start, :recipe_ids])
  defmodule AddItem, do: defstruct([:item_id, :name, :quantity, :unit, :added_by])
  defmodule RemoveItem, do: defstruct([:item_id, :removed_by])
  defmodule CheckItem, do: defstruct([:item_id, :checked_by])
  defmodule UncheckItem, do: defstruct([:item_id, :unchecked_by])

  @type t ::
          %BuildList{}
          | %AddItem{}
          | %RemoveItem{}
          | %CheckItem{}
          | %UncheckItem{}
end
