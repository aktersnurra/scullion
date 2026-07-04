defmodule ToreWeb.SafeReturn do
  @moduledoc """
  Sanitizes user-supplied return-to paths. Only same-origin absolute paths
  are accepted; protocol-relative (//) and backslash (/\\) tricks fall back
  to the default. Clause order is load-bearing: specific rejects must stay
  above the permissive "/" match.
  """

  def path(value, default \\ "/")
  def path("//" <> _, default), do: default
  def path("/\\" <> _, default), do: default
  def path("/" <> _ = p, _default), do: p
  def path(_, default), do: default
end
