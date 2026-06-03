defmodule Tore.Harness.ProjectorRegistry do
  def child_spec(_) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
