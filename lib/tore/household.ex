defmodule Tore.Household do
  @moduledoc """
  Deprecated. Use `Tore.Family` instead.
  """

  @deprecated "Use Tore.Family.get_preferences/0 instead"
  defdelegate get_preferences(), to: Tore.Family

  @deprecated "Use Tore.Family.update_preferences/1 instead"
  defdelegate update_preferences(attrs), to: Tore.Family

  @deprecated "Use Tore.Family.prefs_to_dietary_guidance/1 instead"
  defdelegate prefs_to_dietary_guidance(prefs), to: Tore.Family
end
