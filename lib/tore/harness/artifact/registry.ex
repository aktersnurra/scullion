defmodule Tore.Harness.Artifact.Registry do
  alias Tore.Harness.Artifact.{CostEntry, MemoryUpdate, PantryBeliefUpdate, PlanDiff, RunSummary}

  @registry %{
    "CostEntry" => CostEntry,
    "MemoryUpdate" => MemoryUpdate,
    "PantryBeliefUpdate" => PantryBeliefUpdate,
    "PlanDiff" => PlanDiff,
    "RunSummary" => RunSummary
  }

  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(kind), do: Map.fetch(@registry, kind)

  @spec kinds() :: [String.t()]
  def kinds, do: Map.keys(@registry)

  @spec modules() :: [module()]
  def modules, do: Map.values(@registry)
end
